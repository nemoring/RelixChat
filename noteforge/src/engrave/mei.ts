/**
 * Converts the NoteForge model into MEI 5 for engraving with Verovio.
 *
 * NoteForge owns all musical decisions that MEI expects to be encoded
 * explicitly: displayed vs. implied accidentals, beam groups and tie
 * resolution. Every rendered element carries the model id, so clicks in the
 * SVG map straight back to model objects through `index`.
 */
import type { ChordEvent, ClefKind, Note, Score, TimeSig, VoiceEvent } from '../model/types';
import { Frac, ZERO, add, cmp, div, sub } from '../model/fraction';
import { beamGroupLength, durToFrac, measureLength } from '../model/duration';
import { effectiveKeys, effectiveTimeSigs, staffRefs, voiceLength } from '../model/query';
import { keyAlter, samePitch } from '../model/pitch';

export interface ElementRef {
  kind: 'note' | 'chord' | 'rest';
  staff: number;
  measure: number;
  voice: number;
  eventId: string;
  noteId?: string;
}

export interface MeiResult {
  mei: string;
  index: Map<string, ElementRef>;
}

export const measureSvgId = (m: number) => `nf-m-${m}`;
export const staffSvgId = (s: number, m: number) => `nf-s-${s}-${m}`;

export function parseStaffSvgId(id: string): { staff: number; measure: number } | null {
  const r = /^nf-s-(\d+)-(\d+)$/.exec(id);
  return r ? { staff: Number(r[1]), measure: Number(r[2]) } : null;
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function clefAttrs(c: ClefKind): string {
  switch (c) {
    case 'treble':
      return 'clef.shape="G" clef.line="2"';
    case 'treble8vb':
      return 'clef.shape="G" clef.line="2" clef.dis="8" clef.dis.place="below"';
    case 'bass':
      return 'clef.shape="F" clef.line="4"';
    case 'alto':
      return 'clef.shape="C" clef.line="3"';
    case 'tenor':
      return 'clef.shape="C" clef.line="4"';
    case 'percussion':
      return 'clef.shape="perc" clef.line="3"';
  }
}

const keyAttr = (fifths: number) => (fifths === 0 ? '0' : fifths > 0 ? `${fifths}s` : `${-fifths}f`);

function meterSigXml(ts: TimeSig): string {
  return `<meterSig count="${ts.count}" unit="${ts.unit}"${ts.symbol ? ` sym="${ts.symbol}"` : ''}/>`;
}

const keySigXml = (fifths: number) => `<keySig sig="${keyAttr(fifths)}"/>`;

const ACCID: Record<number, string> = { [-2]: 'ff', [-1]: 'f', 0: 'n', 1: 's', 2: 'x' };

function durAttrs(ev: VoiceEvent): string {
  return `dur="${ev.dur.base}"${ev.dur.dots ? ` dots="${ev.dur.dots}"` : ''}`;
}

interface TieInfo {
  startId: string;
  endId: string;
  measure: number;
  endMeasure: number;
}

/** Resolves ties: a note ties to the equal pitch in the next event of the same voice. */
function resolveTies(score: Score): { ties: TieInfo[]; targets: Set<string> } {
  const ties: TieInfo[] = [];
  const targets = new Set<string>();
  for (const { staff } of staffRefs(score)) {
    for (let v = 0; v < 4; v++) {
      let prev: { ev: ChordEvent; m: number } | null = null;
      for (let m = 0; m < staff.measures.length; m++) {
        const events = staff.measures[m].voices[v] ?? [];
        if (!events.length) {
          prev = null;
          continue;
        }
        for (const ev of events) {
          if (prev && ev.type === 'chord') {
            for (const n of prev.ev.notes) {
              if (!n.tie) continue;
              const target = ev.notes.find((x) => samePitch(x, n));
              if (target) {
                ties.push({ startId: n.id, endId: target.id, measure: prev.m, endMeasure: m });
                targets.add(target.id);
              }
            }
          }
          prev = ev.type === 'chord' ? { ev, m } : null;
        }
      }
    }
  }
  return { ties, targets };
}

/**
 * Decides which notes need a printed accidental. The rule is the standard
 * one: an accidental holds for the rest of the measure on the same line and
 * octave of the same staff (across voices); tied-over notes print none.
 */
function accidentalsForMeasure(voices: VoiceEvent[][], key: number, tieTargets: Set<string>): Map<string, string | null> {
  const items: { t: Frac; v: number; note: Note }[] = [];
  voices.forEach((events, v) => {
    let t = ZERO;
    for (const ev of events) {
      if (ev.type === 'chord') for (const note of ev.notes) items.push({ t, v, note });
      t = add(t, durToFrac(ev.dur));
    }
  });
  items.sort((a, b) => cmp(a.t, b.t) || a.v - b.v);
  const state = new Map<string, number>();
  const shown = new Map<string, string | null>();
  for (const { note } of items) {
    const k = `${note.step}${note.octave}`;
    const cur = state.has(k) ? state.get(k)! : keyAlter(key, note.step);
    if (note.alter !== cur && !tieTargets.has(note.id)) shown.set(note.id, ACCID[note.alter]);
    else shown.set(note.id, null);
    state.set(k, note.alter);
  }
  return shown;
}

/** Splits a voice into beam groups (indices of consecutive beamable chords). */
function beamGroups(events: VoiceEvent[], ts: TimeSig): number[][] {
  const g = beamGroupLength(ts);
  const groups: number[][] = [];
  let cur: number[] = [];
  let curWindow = -1;
  let t = ZERO;
  const flush = () => {
    if (cur.length >= 2) groups.push(cur);
    cur = [];
  };
  events.forEach((ev, i) => {
    const len = durToFrac(ev.dur);
    const end = add(t, len);
    const w0 = Math.floor(div(t, g).n / div(t, g).d);
    const lastPoint = sub(end, { n: 1, d: 1024 });
    const w1 = Math.floor(div(lastPoint, g).n / div(lastPoint, g).d);
    const beamable = ev.type === 'chord' && ev.dur.base >= 8 && w0 === w1;
    if (!beamable || w0 !== curWindow) flush();
    if (beamable) {
      cur.push(i);
      curWindow = w0;
    } else curWindow = -1;
    t = end;
  });
  flush();
  return groups;
}

function noteXml(note: Note, accid: string | null | undefined, durPart: string): string {
  const pitch = `pname="${note.step.toLowerCase()}" oct="${note.octave}"`;
  const acc = accid ? ` accid="${accid}"` : note.alter !== 0 ? ` accid.ges="${ACCID[note.alter]}"` : '';
  return `<note xml:id="${note.id}" ${durPart}${pitch}${acc}/>`;
}

export interface MeiOptions {
  /** Restricts output to a measure range (inclusive) — used for partial previews. */
  from?: number;
  to?: number;
}

export function scoreToMei(score: Score, opts: MeiOptions = {}): MeiResult {
  const index = new Map<string, ElementRef>();
  const refs = staffRefs(score);
  const sigs = effectiveTimeSigs(score);
  const keys = effectiveKeys(score);
  const { ties, targets } = resolveTies(score);
  const tiesByMeasure = new Map<number, TieInfo[]>();
  for (const t of ties) {
    if (!tiesByMeasure.has(t.measure)) tiesByMeasure.set(t.measure, []);
    tiesByMeasure.get(t.measure)!.push(t);
  }
  const from = Math.max(0, opts.from ?? 0);
  const to = Math.min(score.measures.length - 1, opts.to ?? score.measures.length - 1);

  const out: string[] = [];
  const { meta } = score;
  out.push('<?xml version="1.0" encoding="UTF-8"?>');
  out.push('<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.1">');
  out.push('<meiHead><fileDesc><titleStmt>');
  out.push(`<title>${esc(meta.title)}</title>`);
  if (meta.composer) out.push(`<composer>${esc(meta.composer)}</composer>`);
  out.push('</titleStmt><pubStmt/></fileDesc></meiHead>');
  out.push('<music><body><mdiv><score>');

  out.push('<scoreDef>');
  out.push(keySigXml(keys[from]));
  out.push(meterSigXml(sigs[from]));
  // Page header / footer.
  out.push('<pgHead func="first">');
  if (meta.title) out.push(`<rend halign="center" valign="top"><rend fontsize="xx-large">${esc(meta.title)}</rend></rend>`);
  if (meta.subtitle) out.push(`<rend halign="center" valign="top"><lb/><rend fontsize="large">${esc(meta.subtitle)}</rend></rend>`);
  if (meta.composer || meta.arranger) {
    const lines = [meta.composer, meta.arranger ? `обр. ${meta.arranger}` : ''].filter(Boolean).map(esc);
    out.push(`<rend halign="right" valign="bottom">${lines.join('<lb/>')}</rend>`);
  }
  if (meta.lyricist) out.push(`<rend halign="left" valign="bottom">${esc(meta.lyricist)}</rend>`);
  out.push('</pgHead>');
  out.push('<pgFoot func="all">');
  out.push('<rend halign="center"><num label="page">#</num></rend>');
  if (meta.copyright) out.push(`<rend halign="center" valign="bottom"><lb/><rend fontsize="small">${esc(meta.copyright)}</rend></rend>`);
  out.push('</pgFoot>');

  out.push('<staffGrp>');
  score.parts.forEach((part, pi) => {
    const partStaves = refs.filter((r) => r.partIndex === pi);
    const multi = partStaves.length > 1;
    if (multi) out.push(`<staffGrp symbol="brace" bar.thru="true">`);
    if (multi) out.push(`<label>${esc(part.name)}</label><labelAbbr>${esc(part.abbreviation)}</labelAbbr>`);
    partStaves.forEach((r) => {
      const n = refs.indexOf(r) + 1;
      const label = !multi ? `<label>${esc(part.name)}</label>` : '';
      out.push(`<staffDef n="${n}" lines="5" ${clefAttrs(r.staff.clef)}>${label}</staffDef>`);
    });
    if (multi) out.push('</staffGrp>');
  });
  out.push('</staffGrp></scoreDef>');
  out.push('<section>');

  for (let m = from; m <= to; m++) {
    if (m > from) {
      const keyChanged = keys[m] !== keys[m - 1];
      const tsChanged = sigs[m] !== sigs[m - 1] && (sigs[m].count !== sigs[m - 1].count || sigs[m].unit !== sigs[m - 1].unit || sigs[m].symbol !== sigs[m - 1].symbol);
      if (keyChanged || tsChanged) {
        out.push(`<scoreDef>${keyChanged ? keySigXml(keys[m]) : ''}${tsChanged ? meterSigXml(sigs[m]) : ''}</scoreDef>`);
      }
    }
    const right = m === score.measures.length - 1 ? ' right="end"' : '';
    out.push(`<measure xml:id="${measureSvgId(m)}" n="${m + 1}"${right}>`);
    const mlen = measureLength(sigs[m]);
    refs.forEach((r, s) => {
      const sm = r.staff.measures[m];
      out.push(`<staff xml:id="${staffSvgId(s, m)}" n="${s + 1}">`);
      const accids = accidentalsForMeasure(sm.voices, keys[m], targets);
      sm.voices.forEach((events, v) => {
        if (!events.length) return;
        out.push(`<layer n="${v + 1}">`);
        if (events.every((e) => e.type === 'rest') && cmp(voiceLength(events), mlen) === 0) {
          // A measure of silence is engraved as a centred whole-measure rest.
          out.push(`<mRest xml:id="${events[0].id}"/>`);
          index.set(events[0].id, { kind: 'rest', staff: s, measure: m, voice: v, eventId: events[0].id });
        } else {
          const groups = beamGroups(events, sigs[m]);
          const startOf = new Set(groups.map((g) => g[0]));
          const endOf = new Set(groups.map((g) => g[g.length - 1]));
          events.forEach((ev, i) => {
            if (startOf.has(i)) out.push('<beam>');
            if (ev.type === 'rest') {
              out.push(`<rest xml:id="${ev.id}" ${durAttrs(ev)}/>`);
              index.set(ev.id, { kind: 'rest', staff: s, measure: m, voice: v, eventId: ev.id });
            } else if (ev.notes.length === 1) {
              const n = ev.notes[0];
              out.push(noteXml(n, accids.get(n.id), durAttrs(ev) + ' '));
              index.set(n.id, { kind: 'note', staff: s, measure: m, voice: v, eventId: ev.id, noteId: n.id });
            } else {
              out.push(`<chord xml:id="${ev.id}" ${durAttrs(ev)}>`);
              index.set(ev.id, { kind: 'chord', staff: s, measure: m, voice: v, eventId: ev.id });
              for (const n of ev.notes) {
                out.push(noteXml(n, accids.get(n.id), ''));
                index.set(n.id, { kind: 'note', staff: s, measure: m, voice: v, eventId: ev.id, noteId: n.id });
              }
              out.push('</chord>');
            }
            if (endOf.has(i)) out.push('</beam>');
          });
        }
        out.push('</layer>');
      });
      out.push('</staff>');
    });
    if (m === from) {
      const t = score.tempo;
      const unitGlyph: Record<number, string> = { 1: '&#xE1D2;', 2: '&#xE1D3;', 4: '&#xE1D5;', 8: '&#xE1D7;', 16: '&#xE1D9;' };
      const dot = t.beatDots ? '&#xE1E7;' : '';
      const text = t.text ? `${esc(t.text)} ` : '';
      out.push(
        `<tempo xml:id="nf-tempo" tstamp="1" staff="1" place="above" mm="${t.bpm}" mm.unit="${t.beatUnit}"${t.beatDots ? ` mm.dots="${t.beatDots}"` : ''}>${text}<rend glyph.auth="smufl">${unitGlyph[t.beatUnit] ?? unitGlyph[4]}${dot}</rend> = ${t.bpm}</tempo>`,
      );
    }
    for (const t of tiesByMeasure.get(m) ?? []) {
      if (t.endMeasure <= to) out.push(`<tie startid="#${t.startId}" endid="#${t.endId}"/>`);
    }
    out.push('</measure>');
  }
  out.push('</section></score></mdiv></body></music></mei>');
  return { mei: out.join('\n'), index };
}
