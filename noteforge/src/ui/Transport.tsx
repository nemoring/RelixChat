import { useEffect, useMemo, useRef, useState } from 'react';
import { usePlayer, player } from '../playback/player';
import * as P from '../state/playback';
import { useStore } from '../state/store';
import { quarterBpm, scoreDuration } from '../playback/perform';
import { commands } from '../input/commands';

function fmt(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  return (h ? `${h}:${String(m).padStart(2, '0')}` : `${m}`) + `:${String(r).padStart(2, '0')}`;
}

const tip = (id: string) => {
  const c = commands.get(id);
  return c ? (c.keys.length ? `${c.label} (${c.keys[0]})` : c.label) : id;
};

export function Transport() {
  const status = usePlayer((s) => s.status);
  const position = usePlayer((s) => s.position);
  const duration = usePlayer((s) => s.duration);
  const measure = usePlayer((s) => s.measure);
  const speed = usePlayer((s) => s.speed);
  const loop = usePlayer((s) => s.loop);
  const metronome = usePlayer((s) => s.metronome);
  const sf = usePlayer((s) => s.soundfont);
  const score = useStore((s) => s.score);
  const tempo = score.tempo;
  const scoreLen = useMemo(() => scoreDuration(score), [score]);
  const [mixer, setMixer] = useState(false);
  const total = status === 'stopped' ? scoreLen : duration;
  const qpm = Math.round(quarterBpm(tempo) * speed);
  return (
    <div className="transport">
      <div className="tool-group">
        <button className="tool" title={tip('play.restart')} onClick={() => void P.restart()}>
          ⏮
        </button>
        <button className={`tool play${status === 'playing' ? ' active' : ''}`} title={tip('play.toggle')} onClick={() => void P.playPause()}>
          {status === 'playing' ? '⏸' : '▶'}
        </button>
        <button className="tool" title={tip('play.stop')} disabled={status === 'stopped'} onClick={P.stop}>
          ⏹
        </button>
        <button className={`tool wide${loop ? ' active' : ''}`} title={tip('play.loop')} onClick={P.toggleLoop}>
          ⟲ Цикл
        </button>
        <button className={`tool wide${metronome ? ' active' : ''}`} title={tip('play.metronome')} onClick={P.toggleMetronome}>
          Метроном
        </button>
      </div>
      <div className="transport-pos">
        <span className="lcd">Такт {status === 'stopped' ? '—' : measure + 1}</span>
        <span className="lcd">
          {fmt(status === 'stopped' ? 0 : position)} / {fmt(total)}
        </span>
        <span className="lcd" title="Темп с учётом скорости">
          ♩ = {qpm}
        </span>
      </div>
      <label className="speed" title="Скорость воспроизведения">
        <span>Скорость</span>
        <input type="range" min={25} max={200} step={5} value={Math.round(speed * 100)} onChange={(e) => player.setSpeed(Number(e.target.value) / 100)} />
        <button className="speed-value" onClick={() => player.setSpeed(1)} title="Сбросить до 100 %">
          {Math.round(speed * 100)}%
        </button>
      </label>
      <span className="spacer" />
      <span className={`sf-status ${sf.status}`} title={sf.error ?? 'Звуковой банк'}>
        {sf.status === 'ready' ? `🎹 ${sf.name}` : sf.status === 'loading' ? 'Загрузка SoundFont…' : sf.status === 'error' ? 'SoundFont не загружен — встроенный звук' : 'SoundFont загрузится при первом воспроизведении'}
      </span>
      <div className="mixer-anchor">
        <button className={`tool wide${mixer ? ' active' : ''}`} title={tip('play.mixer')} onClick={() => setMixer(!mixer)}>
          Микшер
        </button>
        {mixer && <Mixer onClose={() => setMixer(false)} />}
      </div>
    </div>
  );
}

export function Mixer({ onClose, embedded }: { onClose: () => void; embedded?: boolean }) {
  const channels = usePlayer((s) => s.channels);
  const reverb = usePlayer((s) => s.reverb);
  const outputs = usePlayer((s) => s.midiOutputs);
  const outputId = usePlayer((s) => s.midiOutputId);
  const preview = usePlayer((s) => s.previewNotes);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    void player.refreshMidi();
    if (embedded) return;
    const close = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node) && !(e.target as HTMLElement).closest('.mixer-anchor')) onClose();
    };
    window.addEventListener('mousedown', close);
    return () => window.removeEventListener('mousedown', close);
  }, [onClose, embedded]);
  const group = (prefix: string, title: string) => (
    <div className="mixer-group">
      <h4>{title}</h4>
      {channels
        .filter((c) => c.id.startsWith(prefix))
        .map((c) => (
          <div key={c.id} className="mixer-row">
            <span className="mixer-label">{c.label}</span>
            <input type="range" min={0} max={150} value={Math.round(c.volume * 100)} onChange={(e) => player.setChannel(c.id, { volume: Number(e.target.value) / 100 })} />
            <span className="mixer-val">{Math.round(c.volume * 100)}</span>
            <button className={`ms${c.mute ? ' on mute' : ''}`} title="Выключить" onClick={() => player.setChannel(c.id, { mute: !c.mute })}>
              M
            </button>
            <button className={`ms${c.solo ? ' on solo' : ''}`} title="Соло" onClick={() => player.setChannel(c.id, { solo: !c.solo })}>
              S
            </button>
          </div>
        ))}
    </div>
  );
  return (
    <div className={embedded ? 'mixer-embedded' : 'mixer'} ref={ref}>
      {group('staff-', 'Партии (нотоносцы)')}
      {group('role-', 'Мелодия и сопровождение')}
      <div className="mixer-group">
        <h4>Звук</h4>
        <div className="mixer-row">
          <span className="mixer-label">Реверберация</span>
          <input type="range" min={0} max={100} value={Math.round(reverb * 100)} onChange={(e) => player.setReverb(Number(e.target.value) / 100)} />
          <span className="mixer-val">{Math.round(reverb * 100)}</span>
        </div>
        <label className="mixer-row">
          <span className="mixer-label">Выход</span>
          <select value={outputId ?? ''} onChange={(e) => player.setMidiOutput(e.target.value || null)}>
            <option value="">Встроенный синтезатор (SoundFont)</option>
            {outputs.map((o) => (
              <option key={o.id} value={o.id}>
                MIDI: {o.name}
              </option>
            ))}
          </select>
        </label>
        <label className="mixer-row check">
          <input type="checkbox" checked={preview} onChange={(e) => player.setPreview(e.target.checked)} />
          <span>Проигрывать ноты при вводе и выделении</span>
        </label>
        <div className="mixer-row">
          <button className="small" onClick={() => void P.chooseSoundFont()}>
            Загрузить SoundFont…
          </button>
          <button className="small" onClick={() => void P.useDefaultSoundFont()}>
            Встроенный (GeneralUser GS)
          </button>
        </div>
      </div>
    </div>
  );
}
