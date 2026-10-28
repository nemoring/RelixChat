/**
 * MusicXML 4.0 (partwise) export. Each part keeps its staves; voices 1–4 of
 * staff n are written as MusicXML voices 4(n-1)+1 … 4(n-1)+4. Melody lines
 * are kept as note colours (and restored from colours on import).
 */
import type { ChordEvent, Score, VoiceEvent, Note, Spanner } from '../model/types';
import { Frac, mul, frac, toNumber } from '../model/fraction';
import { eventLen, measureLength } from '../model/duration';
import { effectiveKeys, effectiveTimeSigs, staffRefs, eventIndex, comparePos, clefAt } from '../model/query';
import { accidentalResolver, beamStates, tieTargets } from '../engrave/mei';
import { quarterBpm } from '../playback/perform';
import { xesc } from './xml';
import { APP_VERSION } from '../model/serialize';

const TYPE: Record<number, string> = { 1: 'whole', 2: 'half', 4: 'quarter', 8: 'eighth', 16: '16th', 32: '32nd', 64: '64th' };
const ACC: Record<string, string> = { s: 'sharp', f: 'flat', n: 'natural', x: 'double-sharp', ff: 'flat-flat' };
const CLEF: Record<string, [string, number, number?]> = {
  treble: ['G', 2],
  treble8vb: ['G', 2, -1],
  bass: ['F', 4],
  alto: ['C', 3],
  tenor: ['C', 4],
  percussion: ['percussion', 3],
};
const ARTIC: Record<string, string> = { staccato: 'staccato', staccatissimo: 'staccatissimo', tenuto: 'tenuto', accent: 'accent', marcato: 'strong-accent' };
const ORN: Record<string, string> = { trill: 'trill-mark', mordent: 'mordent', invertedMordent: 'inverted-mordent', turn: 'turn', invertedTurn: 'inverted-turn' };
const JUMP_WORDS: Record<string, string> = { DC: 'D.C.', DCalFine: 'D.C. al Fine', DCalCoda: 'D.C. al Coda', DS: 'D.S.', DSalFine: 'D.S. al Fine', DSalCoda: 'D.S. al Coda' };

function gcd(a: number, b: number): number {
  while (b) [a, b] = [b, a % b];
  return a;
}
const lcm = (a: number, b: number) => (a / gcd(a, b)) * b;

/** Divisions per quarter that express every duration in the score exactly. */
function divisionsFor(score: Score): number {
  let d = 1;
  for (const { staff } of staffRefs(score))
    for (const sm of staff.measures)
      for (const v of sm.voices)
        for (const ev of v) {
          const q = mul(eventLen(ev), frac(4));
          if (q.n) d = lcm(d, q.d);
          if (d > 100000) return 960;
        }
  return d;
}

export function scoreToMusicXml(score: Score): string {
  const divisions = divisionsFor(score);
  const dur = (f: Frac) => Math.round(toNumber(f) * 4 * divisions);
  const refs = staffRefs(score);
  const sigs = effectiveTimeSigs(score);
  const keys = effectiveKeys(score);
  const accid = accidentalResolver(score);
  const tieStops = tieTargets(score);
  const idx = eventIndex(score);
  const lineColor = new Map(score.lines.map((l) => [l.id, l.color]));

  // Spanner endpoints by event id.
  type SpEnd = { sp: Spanner; num: number };
  const starts = new Map<string, SpEnd[]>();
  const ends = new Map<string, SpEnd[]>();
  const counters: Record<string, number> = {};
  for (const sp of score.spanners) {
    const a = idx.get(sp.start);
    const b = idx.get(sp.end);
    if (!a || !b) continue;
    const [s0, e0] = comparePos(a, b) <= 0 ? [a, b] : [b, a];
    counters[sp.type] = ((counters[sp.type] ?? 0) % 6) + 1;
    const e: SpEnd = { sp, num: counters[sp.type] };
    if (!starts.has(s0.ev.id)) starts.set(s0.ev.id, []);
    starts.get(s0.ev.id)!.push(e);
    if (!ends.has(e0.ev.id)) ends.set(e0.ev.id, []);
    ends.get(e0.ev.id)!.push(e);
  }

  const o: string[] = [];
  const { meta } = score;
  o.push('<?xml version="1.0" encoding="UTF-8" standalone="no"?>');
  o.push('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">');
  o.push('<score-partwise version="4.0">');
  o.push(`<work><work-title>${xesc(meta.title)}</work-title></work>`);
  o.push('<identification>');
  if (meta.composer) o.push(`<creator type="composer">${xesc(meta.composer)}</creator>`);
  if (meta.lyricist) o.push(`<creator type="lyricist">${xesc(meta.lyricist)}</creator>`);
  if (meta.arranger) o.push(`<creator type="arranger">${xesc(meta.arranger)}</creator>`);
  if (meta.copyright) o.push(`<rights>${xesc(meta.copyright)}</rights>`);
  o.push(`<encoding><software>NoteForge ${APP_VERSION}</software><encoding-date>${new Date().toISOString().slice(0, 10)}</encoding-date></encoding>`);
  o.push('</identification>');
  if (meta.subtitle) o.push(`<credit page="1"><credit-type>subtitle</credit-type><credit-words>${xesc(meta.subtitle)}</credit-words></credit>`);
  o.push('<part-list>');
  score.parts.forEach((p, i) => {
    o.push(`<score-part id="P${i + 1}"><part-name>${xesc(p.name)}</part-name><part-abbreviation>${xesc(p.abbreviation)}</part-abbreviation>`);
    o.push(`<score-instrument id="P${i + 1}-I1"><instrument-name>${xesc(p.name)}</instrument-name></score-instrument>`);
    o.push(`<midi-instrument id="P${i + 1}-I1"><midi-channel>${i + 1}</midi-channel><midi-program>${p.program + 1}</midi-program></midi-instrument></score-part>`);
  });
  o.push('</part-list>');

  score.parts.forEach((_part, pi) => {
    const staves = refs.map((r, s) => ({ ...r, s })).filter((r) => r.partIndex === pi);
    o.push(`<part id="P${pi + 1}">`);
    for (let m = 0; m < score.measures.length; m++) {
      const mi = score.measures[m];
      const mlen = measureLength(sigs[m]);
      o.push(`<measure number="${m + 1}">`);
      // Left barline: repeat start / volta start.
      const prevVolta = m > 0 ? score.measures[m - 1].volta?.id : undefined;
      const voltaStart = mi.volta && mi.volta.id !== prevVolta;
      if (mi.repeatStart || voltaStart) {
        o.push('<barline location="left">');
        if (mi.repeatStart) o.push('<bar-style>heavy-light</bar-style>');
        if (voltaStart) o.push(`<ending number="${mi.volta!.numbers.join(',')}" type="start">${mi.volta!.numbers.join(', ')}.</ending>`);
        if (mi.repeatStart) o.push('<repeat direction="forward"/>');
        o.push('</barline>');
      }
      // Attributes.
      const attrs: string[] = [];
      if (m === 0) attrs.push(`<divisions>${divisions}</divisions>`);
      if (m === 0 || keys[m] !== keys[m - 1]) attrs.push(`<key><fifths>${keys[m]}</fifths></key>`);
      if (m === 0 || sigs[m] !== sigs[m - 1]) {
        const ts = sigs[m];
        attrs.push(`<time${ts.symbol ? ` symbol="${ts.symbol}"` : ''}><beats>${ts.count}</beats><beat-type>${ts.unit}</beat-type></time>`);
      }
      if (m === 0 && staves.length > 1) attrs.push(`<staves>${staves.length}</staves>`);
      staves.forEach((r, k) => {
        if (m === 0 || r.staff.measures[m].clef) {
          const c = CLEF[clefAt(score, r.s, m)];
          attrs.push(`<clef number="${k + 1}"><sign>${c[0]}</sign><line>${c[1]}</line>${c[2] ? `<clef-octave-change>${c[2]}</clef-octave-change>` : ''}</clef>`);
        }
      });
      if (attrs.length) o.push(`<attributes>${attrs.join('')}</attributes>`);
      // Measure-level directions (written at the start of the first staff).
      if (m === 0 || mi.tempo) {
        const t = m === 0 ? score.tempo : mi.tempo!;
        const unit = TYPE[t.beatUnit] ?? 'quarter';
        o.push(`<direction placement="above"><direction-type>${t.text ? `<words font-weight="bold">${xesc(t.text)}</words></direction-type><direction-type>` : ''}<metronome><beat-unit>${unit}</beat-unit>${t.beatDots ? '<beat-unit-dot/>' : ''}<per-minute>${t.bpm}</per-minute></metronome></direction-type><staff>1</staff><sound tempo="${Math.round(quarterBpm(t) * 100) / 100}"/></direction>`);
      }
      if (mi.rehearsal) o.push(`<direction placement="above"><direction-type><rehearsal>${xesc(mi.rehearsal)}</rehearsal></direction-type><staff>1</staff></direction>`);
      if (mi.section?.title) o.push(`<direction placement="above"><direction-type><words font-size="14" font-weight="bold">${xesc(mi.section.title)}</words></direction-type><staff>1</staff></direction>`);
      if (mi.marker === 'segno') o.push('<direction placement="above"><direction-type><segno/></direction-type><staff>1</staff><sound segno="segno"/></direction>');
      if (mi.marker === 'coda') o.push('<direction placement="above"><direction-type><coda/></direction-type><staff>1</staff><sound coda="coda"/></direction>');

      const acc = accid(m);
      let wroteVoice = false;
      staves.forEach((r, k) => {
        const staffNo = k + 1;
        const sm = r.staff.measures[m];
        sm.voices.forEach((events, v) => {
          if (!events.length) return;
          // Every voice (of every staff) starts at the beginning of the measure.
          if (wroteVoice) o.push(`<backup><duration>${dur(mlen)}</duration></backup>`);
          wroteVoice = true;
          const voiceNo = k * 4 + v + 1;
          const beams = beamStates(events, sigs[m]);
          events.forEach((ev, i) => writeEvent(o, ev, events, i, { staffNo, voiceNo, staves: staves.length, acc, beams, tieStops, starts, ends, lineColor, dur, divisions }));
        });
      });

      // Right barline / navigation at the end of the measure.
      if (mi.marker === 'fine') o.push('<direction placement="above"><direction-type><words>Fine</words></direction-type><staff>1</staff><sound fine="yes"/></direction>');
      if (mi.marker === 'toCoda') o.push('<direction placement="above"><direction-type><words>To Coda</words></direction-type><staff>1</staff><sound tocoda="coda"/></direction>');
      if (mi.jump) {
        const ds = mi.jump.startsWith('DS');
        o.push(`<direction placement="above"><direction-type><words font-style="italic">${JUMP_WORDS[mi.jump]}</words></direction-type><staff>1</staff><sound ${ds ? 'dalsegno="segno"' : 'dacapo="yes"'}/></direction>`);
      }
      const nextVolta = score.measures[m + 1]?.volta?.id;
      const voltaEnd = mi.volta && mi.volta.id !== nextVolta;
      const style = mi.repeatEnd ? 'light-heavy' : mi.barline === 'double' ? 'light-light' : mi.barline === 'final' || m === score.measures.length - 1 ? 'light-heavy' : '';
      if (style || voltaEnd) {
        o.push('<barline location="right">');
        if (style) o.push(`<bar-style>${style}</bar-style>`);
        if (voltaEnd) o.push(`<ending number="${mi.volta!.numbers.join(',')}" type="${mi.repeatEnd ? 'stop' : 'discontinue'}"/>`);
        if (mi.repeatEnd) o.push(`<repeat direction="backward"${mi.repeatEnd > 2 ? ` times="${mi.repeatEnd}"` : ''}/>`);
        o.push('</barline>');
      }
      o.push('</measure>');
    }
    o.push('</part>');
  });
  o.push('</score-partwise>');
  return o.join('\n');
}

interface Ctx {
  staffNo: number;
  voiceNo: number;
  staves: number;
  acc: Map<string, string | null>;
  beams: Map<string, 'begin' | 'continue' | 'end'>;
  tieStops: Set<string>;
  starts: Map<string, { sp: Spanner; num: number }[]>;
  ends: Map<string, { sp: Spanner; num: number }[]>;
  lineColor: Map<string, string>;
  dur: (f: Frac) => number;
  divisions: number;
}

function writeEvent(o: string[], ev: VoiceEvent, events: VoiceEvent[], i: number, c: Ctx) {
  const staffShown = c.staffNo + (ev.type === 'chord' ? (ev.staffShift ?? 0) : 0);
  const staffEl = c.staves > 1 ? `<staff>${Math.max(1, Math.min(c.staves, staffShown))}</staff>` : '';
  const spStart = c.starts.get(ev.id) ?? [];
  const spEnd = c.ends.get(ev.id) ?? [];
  // Directions that start at this event.
  if (ev.type === 'chord' && ev.dynamic)
    o.push(`<direction placement="below"><direction-type><dynamics><${ev.dynamic}/></dynamics></direction-type>${staffEl}</direction>`);
  for (const { sp, num } of spStart) {
    if (sp.type === 'cresc' || sp.type === 'dim') o.push(`<direction placement="below"><direction-type><wedge type="${sp.type === 'cresc' ? 'crescendo' : 'diminuendo'}" number="${num}"/></direction-type>${staffEl}</direction>`);
    if (sp.type === 'pedal') o.push(`<direction placement="below"><direction-type><pedal type="start" line="no"/></direction-type>${c.staves > 1 ? `<staff>${c.staves}</staff>` : ''}</direction>`);
    if (sp.type === 'ottava' && sp.ottava) o.push(`<direction placement="${sp.ottava > 0 ? 'above' : 'below'}"><direction-type><octave-shift type="${sp.ottava > 0 ? 'down' : 'up'}" size="${Math.abs(sp.ottava)}" number="${num}"/></direction-type>${staffEl}</direction>`);
  }
  const tup = ev.tuplet;
  const prevSameTup = tup && i > 0 && events[i - 1].tuplet?.id === tup.id;
  const nextSameTup = tup && i + 1 < events.length && events[i + 1].tuplet?.id === tup.id;
  const timeMod = tup ? `<time-modification><actual-notes>${tup.num}</actual-notes><normal-notes>${tup.den}</normal-notes></time-modification>` : '';
  const type = `<type>${TYPE[ev.dur.base]}</type>${'<dot/>'.repeat(ev.dur.dots)}`;
  const d = c.dur(eventLen(ev));
  if (ev.type === 'rest') {
    const notations: string[] = [];
    if (tup && !prevSameTup) notations.push('<tuplet type="start" bracket="yes"/>');
    if (tup && !nextSameTup) notations.push('<tuplet type="stop"/>');
    if (ev.fermata) notations.push('<fermata type="upright"/>');
    o.push(`<note><rest/><duration>${d}</duration><voice>${c.voiceNo}</voice>${type}${timeMod}${staffEl}${notations.length ? `<notations>${notations.join('')}</notations>` : ''}</note>`);
  } else {
    const color = ev.line ? c.lineColor.get(ev.line) : undefined;
    ev.notes.forEach((n, k) => writeNote(o, ev, n, k, { ...c, staffEl, type, timeMod, d, color, first: k === 0, tupStart: !!tup && !prevSameTup, tupStop: !!tup && !nextSameTup, spStart, spEnd }));
  }
  // Directions that end at this event.
  for (const { sp, num } of spEnd) {
    if (sp.type === 'cresc' || sp.type === 'dim') o.push(`<direction><direction-type><wedge type="stop" number="${num}"/></direction-type>${staffEl}</direction>`);
    if (sp.type === 'pedal') o.push(`<direction><direction-type><pedal type="stop" line="no"/></direction-type>${c.staves > 1 ? `<staff>${c.staves}</staff>` : ''}</direction>`);
    if (sp.type === 'ottava' && sp.ottava) o.push(`<direction><direction-type><octave-shift type="stop" size="${Math.abs(sp.ottava)}" number="${num}"/></direction-type>${staffEl}</direction>`);
  }
}

function writeNote(
  o: string[],
  ev: ChordEvent,
  n: Note,
  k: number,
  c: Ctx & { staffEl: string; type: string; timeMod: string; d: number; color?: string; first: boolean; tupStart: boolean; tupStop: boolean; spStart: { sp: Spanner; num: number }[]; spEnd: { sp: Spanner; num: number }[] },
) {
  const parts: string[] = [];
  parts.push(`<note${c.color ? ` color="${c.color}"` : ''}>`);
  if (ev.grace) parts.push(ev.grace === 'acciaccatura' ? '<grace slash="yes"/>' : '<grace/>');
  if (k > 0) parts.push('<chord/>');
  parts.push(`<pitch><step>${n.step}</step>${n.alter ? `<alter>${n.alter}</alter>` : ''}<octave>${n.octave}</octave></pitch>`);
  if (!ev.grace) parts.push(`<duration>${c.d}</duration>`);
  const stop = c.tieStops.has(n.id);
  if (stop) parts.push('<tie type="stop"/>');
  if (n.tie) parts.push('<tie type="start"/>');
  parts.push(`<voice>${c.voiceNo}</voice>${c.type}`);
  const a = c.acc.get(n.id);
  if (a) parts.push(`<accidental>${ACC[a]}</accidental>`);
  parts.push(c.timeMod);
  if (ev.stem) parts.push(`<stem>${ev.stem}</stem>`);
  parts.push(c.staffEl);
  if (k === 0) {
    const b = c.beams.get(ev.id);
    if (b) parts.push(`<beam number="1">${b}</beam>`);
  }
  const not: string[] = [];
  if (stop) not.push('<tied type="stop"/>');
  if (n.tie) not.push('<tied type="start"/>');
  if (c.first) {
    for (const { sp, num } of c.spEnd) if (sp.type === 'slur') not.push(`<slur type="stop" number="${num}"/>`);
    for (const { sp, num } of c.spStart) if (sp.type === 'slur') not.push(`<slur type="start" number="${num}"/>`);
    if (c.tupStart) not.push('<tuplet type="start" bracket="no"/>');
    if (c.tupStop) not.push('<tuplet type="stop"/>');
    if (ev.artics?.length) not.push(`<articulations>${ev.artics.map((x) => `<${ARTIC[x]}/>`).join('')}</articulations>`);
    if (ev.ornament) not.push(`<ornaments><${ORN[ev.ornament]}/></ornaments>`);
    if (ev.fermata) not.push('<fermata type="upright"/>');
  }
  if (not.length) parts.push(`<notations>${not.join('')}</notations>`);
  parts.push('</note>');
  o.push(parts.join(''));
}
