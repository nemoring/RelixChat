import { describe, it, expect } from 'vitest';
import { createPianoScore } from '../src/model/factory';
import * as E from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { scoreToMusicXml } from '../src/io/musicxml-export';
import { musicXmlToScore } from '../src/io/musicxml-import';
import { parseXml } from '../src/io/xml';
import { staffRefs } from '../src/model/query';
import { perform } from '../src/playback/perform';
import { edit } from './helpers';
import type { Score, Step } from '../src/model/types';

const P = (step: Step, octave: number, alter = 0) => ({ step, octave, alter });

/** Musical content without ids, for comparing scores. */
function content(s: Score) {
  const lineName = new Map(s.lines.map((l) => [l.id, l.color]));
  return {
    measures: s.measures.map(({ id: _id, volta, ...m }) => ({ ...m, volta: volta?.numbers })),
    staves: staffRefs(s).map(({ staff }) => ({
      clef: staff.clef,
      measures: staff.measures.map((sm) => ({
        clef: sm.clef,
        voices: sm.voices.map((v) =>
          v.map((e) => {
            const base = { type: e.type, dur: e.dur, tuplet: e.tuplet ? `${e.tuplet.num}:${e.tuplet.den}` : undefined, fermata: e.fermata };
            if (e.type === 'rest') return base;
            return {
              ...base,
              notes: e.notes.map((n) => `${n.step}${n.alter}${n.octave}${n.tie ? '~' : ''}`),
              artics: e.artics,
              ornament: e.ornament,
              grace: e.grace,
              dynamic: e.dynamic,
              staffShift: e.staffShift,
              stem: e.stem,
              line: e.line ? lineName.get(e.line) : undefined,
            };
          }),
        ),
      })),
    })),
    spanners: s.spanners.map((x) => x.type + (x.ottava ?? '')).sort(),
    tempo: s.tempo,
    meta: s.meta,
  };
}

function rich(): Score {
  return edit(createPianoScore({ title: 'Ноктюрн', composer: 'Автор', measures: 6, keySig: -3, bpm: 72 }), (d) => {
    d.meta.subtitle = 'для фортепиано';
    d.meta.arranger = 'Аранжировщик';
    const line = d.lines[0].id;
    const a = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { type: 'chord', notes: [P('E', 5, -1)], attrs: { line, dynamic: 'p', artics: ['tenuto'] } });
    E.writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 8), { type: 'chord', notes: [P('D', 5)], attrs: { line } });
    E.writeAt(d, 0, 0, 0, frac(3, 8), frac(1, 8), { type: 'chord', notes: [P('C', 5)], attrs: { line, artics: ['staccato', 'accent'] } });
    const z = E.writeAt(d, 0, 0, 0, frac(1, 2), frac(3, 4), { type: 'chord', notes: [P('B', 4, -1), P('G', 4)], attrs: { ornament: 'trill' } });
    E.addSpanner(d, 'slur', a.firstId, z.firstId);
    E.addSpanner(d, 'cresc', a.firstId, z.firstId);
    const l1 = E.writeAt(d, 1, 0, 0, ZERO, frac(1, 2), { type: 'chord', notes: [P('E', 2, -1), P('B', 2, -1)] });
    E.writeAt(d, 1, 0, 0, frac(1, 2), frac(1, 4), { type: 'chord', notes: [P('G', 4)], attrs: { staffShift: -1, line } });
    E.addSpanner(d, 'pedal', l1.firstId, l1.firstId);
    // Second voice in the right hand.
    E.writeAt(d, 0, 1, 1, ZERO, frac(1, 2), { type: 'chord', notes: [P('C', 4)], attrs: { stem: 'down' } });
    E.createTuplet(d, 0, 2, 0, ZERO, frac(1, 4), 3);
    E.writeAt(d, 0, 2, 0, ZERO, frac(1, 8), { type: 'chord', notes: [P('F', 5)] });
    E.writeAt(d, 0, 2, 0, frac(1, 12), frac(1, 8), { type: 'chord', notes: [P('G', 5)] });
    const g = E.writeAt(d, 0, 2, 0, frac(1, 4), frac(1, 4), { type: 'chord', notes: [P('A', 5, -1)], attrs: { fermata: true, dynamic: 'ff' } });
    E.addGrace(d, 0, 2, 0, g.firstId, 'acciaccatura');
    const o1 = E.writeAt(d, 0, 3, 0, ZERO, frac(1, 2), { type: 'chord', notes: [P('C', 6)] });
    const o2 = E.writeAt(d, 0, 3, 0, frac(1, 2), frac(1, 2), { type: 'chord', notes: [P('D', 6)] });
    E.addSpanner(d, 'ottava', o1.firstId, o2.firstId, 8);
    E.setRepeatStart(d, 1, true);
    E.setVolta(d, 3, 3, [1]);
    E.setRepeatEnd(d, 3, 2);
    E.setVolta(d, 4, 4, [2]);
    E.setClef(d, 1, 'treble', 4);
    E.setMeasureTempo(d, 4, { bpm: 60, beatUnit: 4, beatDots: 0, text: 'Adagio' });
    E.setTimeSig(d, 5, { count: 3, unit: 4 });
    E.setMarker(d, 5, 'fine');
    d.measures[2].rehearsal = 'A';
  });
}

describe('MusicXML', () => {
  it('exports well-formed MusicXML 4.0', () => {
    const xml = scoreToMusicXml(rich());
    const doc = parseXml(xml);
    const sp = doc.children.find((c) => c.name === 'score-partwise')!;
    expect(sp.attrs.version).toBe('4.0');
    expect(sp.children.filter((c) => c.name === 'part').length).toBe(1);
    expect(xml).toContain('<staves>2</staves>');
    expect(xml).toContain('<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>');
    expect(xml).toContain('<repeat direction="backward"/>');
    expect(xml).toContain('<ending number="2" type="start">');
  });

  it('round-trips the musical content (export → import)', () => {
    const s = rich();
    const back = musicXmlToScore(scoreToMusicXml(s));
    expect(content(back.score)).toEqual(content(s));
    expect(back.warnings).toEqual([]);
  });

  it('plays the imported score identically', () => {
    const s = rich();
    const back = musicXmlToScore(scoreToMusicXml(s)).score;
    const a = perform(s).notes.map((n) => [n.key, n.start.toFixed(4), n.end.toFixed(4), n.vel]);
    const b = perform(back).notes.map((n) => [n.key, n.start.toFixed(4), n.end.toFixed(4), n.vel]);
    expect(b).toEqual(a);
  });

  it('imports a typical MuseScore-style file (pickup, chords, two voices, backup)', () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="3.1">
  <movement-title>Minuet</movement-title>
  <identification><creator type="composer">J. S. Bach</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="0" implicit="yes">
      <attributes><divisions>2</divisions><key><fifths>1</fifths></key><time><beats>3</beats><beat-type>4</beat-type></time><staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <backup><duration>2</duration></backup>
      <note><rest/><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
    </measure>
    <measure number="1">
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff><beam number="1">begin</beam></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff><beam number="1">end</beam></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>6</duration><voice>2</voice><type>half</type><dot/><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>G</step><octave>3</octave></pitch><duration>4</duration><voice>5</voice><type>half</type><staff>2</staff></note>
      <note><chord/><pitch><step>B</step><octave>3</octave></pitch><duration>4</duration><voice>5</voice><type>half</type><staff>2</staff></note>
      <note><pitch><step>F</step><alter>1</alter><octave>3</octave></pitch><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>`;
    const { score } = musicXmlToScore(xml);
    expect(score.meta.title).toBe('Minuet');
    expect(score.meta.composer).toBe('J. S. Bach');
    expect(score.measures.length).toBe(2);
    expect(score.measures[0].timeSig).toEqual({ count: 1, unit: 4 }); // pickup
    expect(score.measures[1].timeSig).toEqual({ count: 3, unit: 4 });
    expect(score.measures[0].keySig).toBe(1);
    const rh = score.parts[0].staves[0].measures[1];
    expect(rh.voices[0].map((e) => (e.type === 'chord' ? e.notes[0].step : 'r'))).toEqual(['G', 'A', 'B', 'C']);
    expect(rh.voices[1].map((e) => (e.type === 'chord' ? e.notes[0].step + e.dur.base + '.'.repeat(e.dur.dots) : 'r'))).toEqual(['E2.']);
    const lh = score.parts[0].staves[1].measures[1].voices[0];
    expect(lh[0].type === 'chord' && lh[0].notes.map((n) => n.step)).toEqual(['G', 'B']);
    expect(lh[1].type === 'chord' && lh[1].notes[0].alter).toBe(1);
    expect(score.parts[0].staves[1].clef).toBe('bass');
  });

  it('rejects non-MusicXML input with a clear message', () => {
    expect(() => musicXmlToScore('<html></html>')).toThrow(/MusicXML/);
  });
});
