/**
 * Converts the NoteForge model into MEI 5 for engraving with Verovio.
 *
 * NoteForge owns all musical decisions that MEI expects to be encoded
 * explicitly: displayed vs. implied accidentals, beam groups, tie resolution,
 * written octave under 8va lines. Every rendered element carries the model
 * id, so clicks in the SVG map straight back to model objects through `index`.
 */
import type { ChordEvent, ClefKind, JumpKind, Note, Score, TimeSig, VoiceEvent, Tempo } from '../model/types';
import { Frac, ZERO, add, cmp, div, sub, toNumber } from '../model/fraction';
import { beamGroupLength, eventLen, measureLength } from '../model/duration';
import { effectiveKeys, effectiveTimeSigs, staffRefs, voiceLength, eventIndex, comparePos, clefAt } from '../model/query';
import { keyAlter, samePitch } from '../model/pitch';
import { blocksOf } from '../model/edit';

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

/** Id of the MEI element drawn for an event (a one-note chord is written as a <note>). */
export const svgIdOf = (ev: VoiceEvent) => (ev.type === 'chord' && ev.notes.length === 1 ? ev.notes[0].id : ev.id);

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function clefAttrs(c: ClefKind, prefix = 'clef.'): string {
  const [shape, line, dis] = CLEF_DEF[c];
  return `${prefix}shape="${shape}" ${prefix}line="${line}"${dis ? ` ${prefix}dis="8" ${prefix}dis.place="below"` : ''}`;
}

const CLEF_DEF: Record<ClefKind, [string, number, boolean]> = {
  treble: ['G', 2, false],
  treble8vb: ['G', 2, true],
  bass: ['F', 4, false],
  alto: ['C', 3, false],
  tenor: ['C', 4, false],
  percussion: ['perc', 3, false],
};

const keyAttr = (fifths: number) => (fifths === 0 ? '0' : fifths > 0 ? `${fifths}s` : `${-fifths}f`);

function meterSigXml(ts: TimeSig): string {
  return `<meterSig count="${ts.count}" unit="${ts.unit}"${ts.symbol ? ` sym="${ts.symbol}"` : ''}/>`;
}

const keySigXml = (fifths: number) => `<keySig sig="${keyAttr(fifths)}"/>`;

const ACCID: Record<number, string> = { [-2]: 'ff', [-1]: 'f', 0: 'n', 1: 's', 2: 'x' };
const ARTIC: Record<string, string> = { staccato: 'stacc', staccatissimo: 'stacciss', tenuto: 'ten', accent: 'acc', marcato: 'marc' };
const JUMP_TEXT: Record<JumpKind, string> = {
  DC: 'D.C.',
  DCalFine: 'D.C. al Fine',
  DCalCoda: 'D.C. al Coda',
  DS: 'D.S.',
  DSalFine: 'D.S. al Fine',
  DSalCoda: 'D.S. al Coda',
};

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
          if (ev.type === 'chord' && ev.grace) continue;
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
 * octave of the same (displayed) staff, across voices; tied-over notes print none.
 */
function accidentalsForMeasure(score: Score, m: number, key: number, tieTargets: Set<string>, octaveShift: Map<string, number>): Map<string, string | null> {
  const refs = staffRefs(score);
  const byStaff = new Map<number, { t: Frac; v: number; note: Note }[]>();
  refs.forEach((r, s) => {
    r.staff.measures[m].voices.forEach((events, v) => {
      let t = ZERO;
      for (const ev of events) {
        if (ev.type === 'chord') {
          const shown = s + (ev.staffShift ?? 0);
          if (!byStaff.has(shown)) byStaff.set(shown, []);
          for (const note of ev.notes) byStaff.get(shown)!.push({ t, v, note });
        }
        t = add(t, eventLen(ev));
      }
    });
  });
  const shown = new Map<string, string | null>();
  for (const items of byStaff.values()) {
    items.sort((a, b) => cmp(a.t, b.t) || a.v - b.v);
    const state = new Map<string, number>();
    for (const { note } of items) {
      const k = `${note.step}${note.octave + (octaveShift.get(note.id) ?? 0)}`;
      const cur = state.has(k) ? state.get(k)! : keyAlter(key, note.step);
      if (note.alter !== cur && !tieTargets.has(note.id)) shown.set(note.id, ACCID[note.alter]);
      else shown.set(note.id, null);
      state.set(k, note.alter);
    }
  }
  return shown;
}

const beamable = (ev: VoiceEvent) => ev.type === 'chord' && !ev.grace && ev.dur.base >= 8 && ev.beam !== 'none';

/** Splits plain (non-tuplet) events into beam groups by beat windows and manual beam marks. */
function beamGroups(events: { ev: VoiceEvent; start: Frac }[], ts: TimeSig): number[][] {
  const g = beamGroupLength(ts);
  const groups: number[][] = [];
  let cur: number[] = [];
  let curWindow = -1;
  const flush = () => {
    if (cur.length >= 2) groups.push(cur);
    cur = [];
  };
  events.forEach(({ ev, start }, i) => {
    const end = add(start, eventLen(ev));
    const q0 = div(start, g);
    const w0 = Math.floor(q0.n / q0.d);
    const lastPoint = sub(end, { n: 1, d: 4096 });
    const q1 = div(lastPoint, g);
    const w1 = Math.floor(q1.n / q1.d);
    const ok = beamable(ev) && (w0 === w1 || (ev.type === 'chord' && ev.beam === 'join'));
    const join = ev.type === 'chord' && ev.beam === 'join' && cur.length > 0;
    if (!ok || (!join && w0 !== curWindow) || (ev.type === 'chord' && ev.beam === 'break')) flush();
    if (ok) {
      cur.push(i);
      curWindow = w0;
    } else curWindow = -1;
  });
  flush();
  return groups;
}

export interface MeiOptions {
  /** Restricts output to a measure range (inclusive) — used for fast partial re-layout. */
  from?: number;
  to?: number;
  /** Measures before which a system break is encoded. */
  systemBreaks?: number[];
  /** Measures before which a page break is encoded. */
  pageBreaks?: number[];
  /** Literal page number for a partial render (instead of automatic numbering). */
  pageLabel?: string;
}

function tempoXml(t: Tempo, id: string): string {
  const unitGlyph: Record<number, string> = { 1: '&#xE1D2;', 2: '&#xE1D3;', 4: '&#xE1D5;', 8: '&#xE1D7;', 16: '&#xE1D9;' };
  const dot = t.beatDots ? '&#xE1E7;' : '';
  const mm = `<rend glyph.auth="smufl">${unitGlyph[t.beatUnit] ?? unitGlyph[4]}${dot}</rend> = ${t.bpm}`;
  const body = t.text ? `${esc(t.text)} (${mm})` : mm;
  return `<tempo xml:id="${id}" tstamp="1" staff="1" place="above" mm="${t.bpm}" mm.unit="${t.beatUnit}"${t.beatDots ? ` mm.dots="${t.beatDots}"` : ''}>${body}</tempo>`;
}

/** Notes written an octave (or two) away from sounding pitch because of 8va/8vb lines. */
function octaveShifts(score: Score): { shifts: Map<string, number>; lines: { start: string; end: string; staff: number; ottava: number; measure: number }[] } {
  const shifts = new Map<string, number>();
  const lines: { start: string; end: string; staff: number; ottava: number; measure: number }[] = [];
  const idx = eventIndex(score);
  const refs = staffRefs(score);
  for (const sp of score.spanners) {
    if (sp.type !== 'ottava' || !sp.ottava) continue;
    const a = idx.get(sp.start);
    const b = idx.get(sp.end);
    if (!a || !b) continue;
    const [s0, e0] = comparePos(a, b) <= 0 ? [a, b] : [b, a];
    const delta = sp.ottava === 8 ? -1 : sp.ottava === 15 ? -2 : sp.ottava === -8 ? 1 : 2;
    lines.push({ start: svgIdOf(s0.ev), end: svgIdOf(e0.ev), staff: s0.staff, ottava: sp.ottava, measure: s0.measure });
    const st = refs[s0.staff].staff;
    for (let m = s0.measure; m <= e0.measure; m++) {
      st.measures[m].voices.forEach((events) => {
        let t = ZERO;
        for (const ev of events) {
          const inside = comparePos({ measure: m, start: t }, s0) >= 0 && comparePos({ measure: m, start: t }, e0) <= 0;
          if (inside && ev.type === 'chord') for (const n of ev.notes) shifts.set(n.id, delta);
          t = add(t, eventLen(ev));
        }
      });
    }
  }
  return { shifts, lines };
}

export function scoreToMei(score: Score, opts: MeiOptions = {}): MeiResult {
  const index = new Map<string, ElementRef>();
  const refs = staffRefs(score);
  const sigs = effectiveTimeSigs(score);
  const keys = effectiveKeys(score);
  const evIdx = eventIndex(score);
  const { ties, targets } = resolveTies(score);
  const { shifts: octShift, lines: octLines } = octaveShifts(score);
  const tiesByMeasure = new Map<number, TieInfo[]>();
  for (const t of ties) {
    if (!tiesByMeasure.has(t.measure)) tiesByMeasure.set(t.measure, []);
    tiesByMeasure.get(t.measure)!.push(t);
  }
  // Control events (spanners) grouped by the measure where they start.
  const controls = new Map<number, string[]>();
  const addControl = (m: number, xml: string) => {
    if (!controls.has(m)) controls.set(m, []);
    controls.get(m)!.push(xml);
  };
  for (const sp of score.spanners) {
    const a = evIdx.get(sp.start);
    const b = evIdx.get(sp.end);
    if (!a || !b) continue;
    const [s0, e0] = comparePos(a, b) <= 0 ? [a, b] : [b, a];
    const sid = svgIdOf(s0.ev);
    const eid = svgIdOf(e0.ev);
    if (sp.type === 'slur') addControl(s0.measure, `<slur xml:id="${sp.id}" startid="#${sid}" endid="#${eid}"/>`);
    else if (sp.type === 'cresc' || sp.type === 'dim')
      addControl(s0.measure, `<hairpin xml:id="${sp.id}" form="${sp.type === 'cresc' ? 'cres' : 'dim'}" startid="#${sid}" endid="#${eid}" staff="${s0.staff + 1}" place="below"/>`);
    else if (sp.type === 'pedal') {
      addControl(s0.measure, `<pedal xml:id="${sp.id}" dir="down" startid="#${sid}" staff="${refs.length > 1 ? refs.length : 1}" form="pedstar"/>`);
      const ts = sigs[e0.measure];
      const tstamp = 1 + toNumber(e0.end) * ts.unit - 0.1;
      addControl(e0.measure, `<pedal xml:id="${sp.id}-up" dir="up" tstamp="${tstamp.toFixed(3)}" staff="${refs.length > 1 ? refs.length : 1}" form="pedstar"/>`);
    }
  }
  for (const o of octLines) {
    const dis = Math.abs(o.ottava);
    addControl(o.measure, `<octave startid="#${o.start}" endid="#${o.end}" staff="${o.staff + 1}" dis="${dis}" dis.place="${o.ottava > 0 ? 'above' : 'below'}"/>`);
  }

  const from = Math.max(0, opts.from ?? 0);
  const to = Math.min(score.measures.length - 1, opts.to ?? score.measures.length - 1);
  const layout = score.layout;
  const sysBreaks = new Set(opts.systemBreaks ?? []);
  const pageBreaks = new Set(opts.pageBreaks ?? []);
  for (let m = from + 1; m <= to; m++) {
    const mi = score.measures[m];
    if (mi.breakBefore === 'page' || mi.section?.newPage) pageBreaks.add(m);
    else if (mi.breakBefore === 'system' || mi.section) sysBreaks.add(m);
    if (layout.measuresPerSystem > 0 && (m - from) % layout.measuresPerSystem === 0) sysBreaks.add(m);
  }

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
  if (layout.showHeader && from === 0) {
    out.push('<pgHead func="first">');
    if (meta.title) out.push(`<rend halign="center" valign="top"><rend fontsize="xx-large">${esc(meta.title)}</rend></rend>`);
    if (meta.subtitle) out.push(`<rend halign="center" valign="top"><lb/><rend fontsize="large">${esc(meta.subtitle)}</rend></rend>`);
    if (meta.composer || meta.arranger) {
      const lines = [meta.composer, meta.arranger ? `обр. ${meta.arranger}` : ''].filter(Boolean).map(esc);
      out.push(`<rend halign="right" valign="bottom">${lines.join('<lb/>')}</rend>`);
    }
    if (meta.lyricist) out.push(`<rend halign="left" valign="bottom">${esc(meta.lyricist)}</rend>`);
    out.push('</pgHead>');
  }
  out.push('<pgFoot func="all">');
  if (layout.showPageNumbers) out.push(`<rend halign="center">${opts.pageLabel ? esc(opts.pageLabel) : '<num label="page">#</num>'}</rend>`);
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
      out.push(`<staffDef n="${n}" lines="5" ${clefAttrs(clefAt(score, n - 1, from))}>${label}</staffDef>`);
    });
    if (multi) out.push('</staffGrp>');
  });
  out.push('</staffGrp></scoreDef>');
  out.push('<section>');

  let openEnding: string | null = null;
  for (let m = from; m <= to; m++) {
    const mi = score.measures[m];
    // Volta brackets (endings) wrap consecutive measures with the same id.
    const voltaId = mi.volta?.id ?? null;
    if (openEnding && openEnding !== voltaId) {
      out.push('</ending>');
      openEnding = null;
    }
    if (pageBreaks.has(m)) out.push('<pb/>');
    else if (sysBreaks.has(m)) out.push('<sb/>');
    if (m > from) {
      const keyChanged = keys[m] !== keys[m - 1];
      const tsChanged = sigs[m] !== sigs[m - 1] && (sigs[m].count !== sigs[m - 1].count || sigs[m].unit !== sigs[m - 1].unit || sigs[m].symbol !== sigs[m - 1].symbol);
      const clefChanges = refs.map((r, s) => (r.staff.measures[m].clef ? `<staffDef n="${s + 1}" ${clefAttrs(r.staff.measures[m].clef!)}/>` : '')).join('');
      if (keyChanged || tsChanged || clefChanges) {
        out.push(`<scoreDef>${keyChanged ? keySigXml(keys[m]) : ''}${tsChanged ? meterSigXml(sigs[m]) : ''}${clefChanges ? `<staffGrp>${clefChanges}</staffGrp>` : ''}</scoreDef>`);
      }
    }
    if (voltaId && openEnding !== voltaId) {
      const label = mi.volta!.numbers.join(', ');
      out.push(`<ending n="${esc(label)}" label="${esc(label)}.">`);
      openEnding = voltaId;
    }
    let right = '';
    if (mi.repeatEnd) right = 'rptend';
    else if (mi.barline === 'double') right = 'dbl';
    else if (mi.barline === 'final' || m === score.measures.length - 1) right = 'end';
    const left = mi.repeatStart ? ' left="rptstart"' : '';
    out.push(`<measure xml:id="${measureSvgId(m)}" n="${m + 1}"${left}${right ? ` right="${right}"` : ''}>`);
    const mlen = measureLength(sigs[m]);
    const accids = accidentalsForMeasure(score, m, keys[m], targets, octShift);
    const ctl: string[] = [];
    refs.forEach((r, s) => {
      const sm = r.staff.measures[m];
      out.push(`<staff xml:id="${staffSvgId(s, m)}" n="${s + 1}">`);
      sm.voices.forEach((events, v) => {
        if (!events.length) return;
        out.push(`<layer n="${v + 1}">`);
        if (events.every((e) => e.type === 'rest' && !e.tuplet) && cmp(voiceLength(events), mlen) === 0) {
          // A measure of silence is engraved as a centred whole-measure rest.
          const ferm = events.some((e) => e.fermata) ? ' fermata="above"' : '';
          out.push(`<mRest xml:id="${events[0].id}"${ferm}/>`);
          for (const e of events) index.set(e.id, { kind: 'rest', staff: s, measure: m, voice: v, eventId: events[0].id });
        } else {
          writeLayer(out, events, s, m, v, sigs[m], accids, octShift, index, ctl, refs.length);
        }
        out.push('</layer>');
      });
      out.push('</staff>');
    });
    out.push(...ctl);
    // Tempo marks.
    if (m === from) out.push(tempoXml(m === 0 ? score.tempo : (score.measures[m].tempo ?? temposBefore(score, m)), `nf-tempo-${m}`));
    else if (mi.tempo) out.push(tempoXml(mi.tempo, `nf-tempo-${m}`));
    // Navigation marks.
    const ts = sigs[m];
    if (mi.marker === 'segno') out.push(`<repeatMark xml:id="nf-mk-${m}" func="segno" tstamp="1" staff="1" place="above"/>`);
    if (mi.marker === 'coda') out.push(`<repeatMark xml:id="nf-mk-${m}" func="coda" tstamp="1" staff="1" place="above"/>`);
    if (mi.marker === 'fine') out.push(`<repeatMark xml:id="nf-mk-${m}" func="fine" tstamp="${ts.count}" staff="1" place="above"/>`);
    if (mi.marker === 'toCoda') out.push(`<dir xml:id="nf-mk-${m}" tstamp="${ts.count}" staff="1" place="above">To Coda <rend glyph.auth="smufl">&#xE048;</rend></dir>`);
    if (mi.jump) out.push(`<dir xml:id="nf-jmp-${m}" tstamp="${ts.count}" staff="1" place="above"><rend fontstyle="italic">${JUMP_TEXT[mi.jump]}</rend></dir>`);
    if (mi.rehearsal) out.push(`<reh xml:id="nf-reh-${m}" tstamp="0" staff="1" place="above"><rend rend="box">${esc(mi.rehearsal)}</rend></reh>`);
    if (mi.section?.title) out.push(`<dir xml:id="nf-sec-${m}" tstamp="0" staff="1" place="above"><rend fontsize="large" fontweight="bold">${esc(mi.section.title)}</rend></dir>`);
    for (const c of controls.get(m) ?? []) out.push(c);
    for (const t of tiesByMeasure.get(m) ?? []) {
      if (t.endMeasure <= to) out.push(`<tie startid="#${t.startId}" endid="#${t.endId}"/>`);
    }
    out.push('</measure>');
  }
  if (openEnding) out.push('</ending>');
  out.push('</section></score></mdiv></body></music></mei>');
  return { mei: out.join('\n'), index };
}

function temposBefore(score: Score, m: number): Tempo {
  for (let i = m; i > 0; i--) if (score.measures[i].tempo) return score.measures[i].tempo!;
  return score.tempo;
}

/** Writes one layer: tuplets, beams, grace notes, chords, rests and their marks. */
function writeLayer(
  out: string[],
  events: VoiceEvent[],
  s: number,
  m: number,
  v: number,
  ts: TimeSig,
  accids: Map<string, string | null>,
  octShift: Map<string, number>,
  index: Map<string, ElementRef>,
  ctl: string[],
  nStaves: number,
) {
  const blocks = blocksOf(events);
  // Plain (non-tuplet) items for beat-based beaming.
  type Item = { ev: VoiceEvent; start: Frac };
  const writeEvent = (ev: VoiceEvent) => {
    if (ev.type === 'rest') {
      out.push(`<rest xml:id="${ev.id}" ${durAttrs(ev)}${ev.fermata ? ' fermata="above"' : ''}/>`);
      index.set(ev.id, { kind: 'rest', staff: s, measure: m, voice: v, eventId: ev.id });
      return;
    }
    const attrs: string[] = [];
    if (ev.stem) attrs.push(`stem.dir="${ev.stem}"`);
    if (ev.staffShift && s + ev.staffShift >= 0 && s + ev.staffShift < nStaves) attrs.push(`staff="${s + 1 + ev.staffShift}"`);
    if (ev.grace === 'acciaccatura') attrs.push('grace="unacc" stem.mod="1slash"');
    else if (ev.grace === 'appoggiatura') attrs.push('grace="acc"');
    if (ev.fermata) attrs.push('fermata="above"');
    const artic = ev.artics?.length ? `<artic artic="${ev.artics.map((a) => ARTIC[a]).join(' ')}"/>` : '';
    const a = attrs.length ? ' ' + attrs.join(' ') : '';
    if (ev.notes.length === 1) {
      const n = ev.notes[0];
      out.push(noteXml(n, accids.get(n.id), `${durAttrs(ev)}${a}`, octShift.get(n.id) ?? 0, artic));
      index.set(n.id, { kind: 'note', staff: s, measure: m, voice: v, eventId: ev.id, noteId: n.id });
    } else {
      out.push(`<chord xml:id="${ev.id}" ${durAttrs(ev)}${a}>${artic}`);
      index.set(ev.id, { kind: 'chord', staff: s, measure: m, voice: v, eventId: ev.id });
      for (const n of ev.notes) {
        out.push(noteXml(n, accids.get(n.id), '', octShift.get(n.id) ?? 0, ''));
        index.set(n.id, { kind: 'note', staff: s, measure: m, voice: v, eventId: ev.id, noteId: n.id });
      }
      out.push('</chord>');
    }
    const startId = ev.notes.length === 1 ? ev.notes[0].id : ev.id;
    const shown = s + 1 + (ev.staffShift ?? 0);
    if (ev.dynamic) ctl.push(`<dynam xml:id="nf-dyn-${ev.id}" startid="#${startId}" staff="${shown}" place="below">${ev.dynamic}</dynam>`);
    if (ev.ornament === 'trill') ctl.push(`<trill xml:id="nf-orn-${ev.id}" startid="#${startId}" staff="${shown}" place="above"/>`);
    else if (ev.ornament === 'mordent') ctl.push(`<mordent xml:id="nf-orn-${ev.id}" startid="#${startId}" staff="${shown}" form="lower" place="above"/>`);
    else if (ev.ornament === 'invertedMordent') ctl.push(`<mordent xml:id="nf-orn-${ev.id}" startid="#${startId}" staff="${shown}" form="upper" place="above"/>`);
    else if (ev.ornament === 'turn') ctl.push(`<turn xml:id="nf-orn-${ev.id}" startid="#${startId}" staff="${shown}" form="upper" place="above"/>`);
    else if (ev.ornament === 'invertedTurn') ctl.push(`<turn xml:id="nf-orn-${ev.id}" startid="#${startId}" staff="${shown}" form="lower" place="above"/>`);
  };

  let run: Item[] = [];
  const flushRun = () => {
    const groups = beamGroups(run, ts);
    const startOf = new Set(groups.map((g) => g[0]));
    const endOf = new Set(groups.map((g) => g[g.length - 1]));
    run.forEach((it, i) => {
      if (startOf.has(i)) out.push('<beam>');
      writeEvent(it.ev);
      if (endOf.has(i)) out.push('</beam>');
    });
    run = [];
  };
  for (const b of blocks) {
    if (!b.tuplet) {
      run.push({ ev: b.events[0], start: b.start });
      continue;
    }
    flushRun();
    const tup = b.tuplet;
    out.push(`<tuplet num="${tup.num}" numbase="${tup.den}" num.visible="true" bracket.visible="${b.events.every(beamable) ? 'false' : 'true'}">`);
    // Inside a tuplet consecutive beamable notes share one beam.
    let group: VoiceEvent[] = [];
    const flushGroup = () => {
      if (group.length >= 2) {
        out.push('<beam>');
        group.forEach(writeEvent);
        out.push('</beam>');
      } else group.forEach(writeEvent);
      group = [];
    };
    for (const ev of b.events) {
      if (beamable(ev) && !(ev.type === 'chord' && ev.beam === 'break' && group.length)) group.push(ev);
      else {
        flushGroup();
        if (beamable(ev)) group.push(ev);
        else writeEvent(ev);
      }
    }
    flushGroup();
    out.push('</tuplet>');
  }
  flushRun();
}

function noteXml(note: Note, accid: string | null | undefined, attrs: string, shift: number, inner: string): string {
  const oct = note.octave + shift;
  const pitch = `pname="${note.step.toLowerCase()}" oct="${oct}"${shift ? ` oct.ges="${note.octave}"` : ''}`;
  const acc = accid ? ` accid="${accid}"` : note.alter !== 0 ? ` accid.ges="${ACCID[note.alter]}"` : '';
  const a = attrs ? ` ${attrs}` : '';
  return inner ? `<note xml:id="${note.id}"${a} ${pitch}${acc}>${inner}</note>` : `<note xml:id="${note.id}"${a} ${pitch}${acc}/>`;
}

/** Accidental display decisions for every measure (shared with MusicXML export). */
export function accidentalResolver(score: Score): (m: number) => Map<string, string | null> {
  const keys = effectiveKeys(score);
  const { targets } = resolveTies(score);
  const { shifts } = octaveShifts(score);
  return (m) => accidentalsForMeasure(score, m, keys[m], targets, shifts);
}

/** Tie targets (notes that continue a tie) for MusicXML tie stops. */
export function tieTargets(score: Score): Set<string> {
  return resolveTies(score).targets;
}

/** Beam begin/continue/end per event of a layer, exactly as engraved. */
export function beamStates(events: VoiceEvent[], ts: TimeSig): Map<string, 'begin' | 'continue' | 'end'> {
  const out = new Map<string, 'begin' | 'continue' | 'end'>();
  const mark = (group: VoiceEvent[]) => {
    if (group.length < 2) return;
    group.forEach((ev, i) => out.set(ev.id, i === 0 ? 'begin' : i === group.length - 1 ? 'end' : 'continue'));
  };
  let run: { ev: VoiceEvent; start: Frac }[] = [];
  const flushRun = () => {
    for (const g of beamGroups(run, ts)) mark(g.map((i) => run[i].ev));
    run = [];
  };
  for (const b of blocksOf(events)) {
    if (!b.tuplet) {
      run.push({ ev: b.events[0], start: b.start });
      continue;
    }
    flushRun();
    let group: VoiceEvent[] = [];
    for (const ev of b.events) {
      if (beamable(ev) && !(ev.type === 'chord' && ev.beam === 'break' && group.length)) group.push(ev);
      else {
        mark(group);
        group = beamable(ev) ? [ev] : [];
      }
    }
    mark(group);
  }
  flushRun();
  return out;
}
