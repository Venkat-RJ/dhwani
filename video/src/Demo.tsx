import React from "react";
import {
  AbsoluteFill,
  Sequence,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";

const GREEN = "#39FF14";
const AMBER = "#FFB000";
const BG = "#07070C";
const MONO = "Menlo, ui-monospace, monospace";
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const Scene: React.FC<{ dur: number; children: React.ReactNode }> = ({ dur, children }) => {
  const f = useCurrentFrame();
  const opacity = interpolate(f, [0, 14, dur - 14, dur], [0, 1, 1, 0], clamp);
  return <AbsoluteFill style={{ opacity, justifyContent: "center", alignItems: "center" }}>{children}</AbsoluteFill>;
};

const Waveform: React.FC<{ n?: number; size?: number; active?: boolean }> = ({ n = 23, size = 1, active = true }) => {
  const f = useCurrentFrame();
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 * size, height: 130 * size }}>
      {Array.from({ length: n }).map((_, i) => {
        const wobble = (0.5 + 0.5 * Math.sin(f * 0.28 + i * 0.55)) * (0.35 + 0.65 * Math.abs(Math.sin(i * 0.8)));
        const lv = active ? Math.max(0.07, wobble) : 0.07;
        return (
          <div key={i} style={{ width: 8 * size, height: 8 + lv * 120 * size, borderRadius: 6, background: GREEN, boxShadow: `0 0 ${9 * size}px ${GREEN}aa` }} />
        );
      })}
    </div>
  );
};

const card = (extra: React.CSSProperties = {}): React.CSSProperties => ({
  background: "#000",
  border: `1px solid ${GREEN}`,
  borderRadius: 22,
  boxShadow: `0 0 28px ${GREEN}44, inset 0 0 60px ${GREEN}11`,
  ...extra,
});

const Caption: React.FC<{ text: string; color?: string }> = ({ text, color = "#dfffe0" }) => (
  <div style={{ position: "absolute", bottom: 60, width: "100%", textAlign: "center", fontFamily: MONO, fontSize: 28, color }}>{text}</div>
);

// ---- Scenes ----

const Title: React.FC = () => {
  const f = useCurrentFrame();
  const full = "lokaah talky";
  const chars = Math.floor(interpolate(f, [6, 44], [0, full.length], clamp));
  const blink = Math.floor(f / 15) % 2 === 0;
  return (
    <Scene dur={80}>
      <div style={{ fontFamily: MONO, fontSize: 84, color: GREEN, fontWeight: 600, textShadow: `0 0 24px ${GREEN}aa` }}>
        {full.slice(0, chars)}<span style={{ opacity: blink ? 1 : 0.15 }}>▍</span>
      </div>
      <div style={{ marginTop: 18, fontFamily: MONO, fontSize: 28, color: "#9affa0" }}>voice dictation for macOS</div>
    </Scene>
  );
};

const WhatIs: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: f - 6, fps, config: { damping: 14 } });
  const listening = f > 70;
  return (
    <Scene dur={150}>
      <div style={{ transform: `scale(${0.6 + pop * 0.4})` }}>
        <div style={{ ...card(), padding: "30px 46px", display: "flex", alignItems: "center", gap: 26 }}>
          <Waveform n={5} size={0.9} active={listening} />
          <div style={{ fontFamily: MONO, fontSize: 34, color: listening ? GREEN : "#eaffea" }}>{listening ? "listening…" : "lokaah talky"}</div>
          {listening && (
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginLeft: 8 }}>
              <div style={{ width: 12, height: 12, borderRadius: 6, background: AMBER, boxShadow: `0 0 10px ${AMBER}` }} />
              <span style={{ fontFamily: MONO, fontSize: 22, color: AMBER }}>REC</span>
            </div>
          )}
        </div>
      </div>
      <Caption text={listening ? "Speak — your words appear at the cursor." : "A tiny widget that floats on your screen."} />
    </Scene>
  );
};

const Step: React.FC<{ n: string; appearAt: number; children: React.ReactNode }> = ({ n, appearAt, children }) => {
  const f = useCurrentFrame();
  const a = interpolate(f, [appearAt, appearAt + 16], [0, 1], clamp);
  return (
    <div style={{ opacity: a, transform: `translateY(${interpolate(a, [0, 1], [16, 0])}px)`, display: "flex", alignItems: "flex-start", gap: 18 }}>
      <div style={{ ...card({ borderRadius: 999 }), minWidth: 44, height: 44, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: MONO, fontSize: 24, color: GREEN }}>{n}</div>
      <div style={{ fontFamily: MONO, fontSize: 27, color: "#eaffea", paddingTop: 6, lineHeight: 1.3 }}>{children}</div>
    </div>
  );
};

const Install: React.FC = () => {
  return (
    <Scene dur={250}>
      <div style={{ position: "absolute", top: 70, width: "100%", textAlign: "center", fontFamily: MONO, fontSize: 40, color: GREEN, fontWeight: 600, textShadow: `0 0 20px ${GREEN}aa` }}>Install — about a minute</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 26, width: 980 }}>
        <Step n="1" appearAt={18}>Download <b style={{ color: GREEN }}>Lokaah-Talky.dmg</b> and open it</Step>
        <Step n="2" appearAt={54}>Drag <b style={{ color: GREEN }}>Lokaah Talky</b> → <b style={{ color: GREEN }}>Applications</b></Step>
        <Step n="3" appearAt={92}>
          In Terminal, run once:
          <div style={{ ...card({ borderColor: `${GREEN}66`, borderRadius: 10 }), marginTop: 10, padding: "12px 16px", fontSize: 21, color: GREEN }}>
            xattr -dr com.apple.quarantine "/Applications/Lokaah&nbsp;Talky.app"
          </div>
        </Step>
        <Step n="4" appearAt={140}>Open it → allow <b style={{ color: GREEN }}>Microphone</b> · <b style={{ color: GREEN }}>Speech</b> · <b style={{ color: GREEN }}>Accessibility</b></Step>
      </div>
    </Scene>
  );
};

const HowToUse: React.FC = () => {
  const f = useCurrentFrame();
  const cmd = "open the deploy logs and tail the last fifty lines";
  const chars = Math.floor(interpolate(f, [40, 150], [0, cmd.length], clamp));
  const blink = Math.floor(f / 15) % 2 === 0;
  return (
    <Scene dur={180}>
      <div style={{ position: "absolute", top: 64, width: "100%", textAlign: "center", fontFamily: MONO, fontSize: 38, color: GREEN, fontWeight: 600 }}>How to use</div>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 30, marginTop: 20 }}>
        <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
          <span style={{ ...card({ borderRadius: 12 }), padding: "12px 20px", fontFamily: MONO, fontSize: 30, color: GREEN }}>⌥ Space</span>
          <span style={{ fontFamily: MONO, fontSize: 28, color: "#9affa0" }}>then talk</span>
        </div>
        <div style={{ ...card({ borderColor: `${GREEN}88` }), width: 860, height: 180, padding: 24, fontFamily: MONO, fontSize: 25, color: GREEN, textAlign: "left" }}>
          <div style={{ color: "#7CFC7C", opacity: 0.6, marginBottom: 12 }}>● ● ●  terminal</div>
          <span style={{ color: AMBER }}>$ </span><span>{cmd.slice(0, chars)}</span><span style={{ opacity: blink ? 1 : 0.1 }}>▍</span>
        </div>
      </div>
      <Caption text="Your words type straight into whatever app is focused." />
    </Scene>
  );
};

const Features: React.FC = () => {
  const f = useCurrentFrame();
  const items = ["On-device & private — audio never leaves your Mac", "Long conversations, nothing cut off", "Every dictation saved to your history"];
  return (
    <Scene dur={120}>
      <div style={{ display: "flex", flexDirection: "column", gap: 30 }}>
        {items.map((t, i) => {
          const a = interpolate(f, [10 + i * 18, 28 + i * 18], [0, 1], clamp);
          return (
            <div key={i} style={{ opacity: a, transform: `translateX(${interpolate(a, [0, 1], [-40, 0])}px)`, display: "flex", alignItems: "center", gap: 18, fontFamily: MONO, fontSize: 32, color: "#eaffea" }}>
              <span style={{ color: GREEN, textShadow: `0 0 12px ${GREEN}` }}>▸</span>{t}
            </div>
          );
        })}
      </div>
    </Scene>
  );
};

const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: f - 4, fps, config: { damping: 13 } });
  return (
    <Scene dur={90}>
      <div style={{ transform: `scale(${0.7 + s * 0.3})`, textAlign: "center" }}>
        <Waveform n={9} size={1.1} />
        <div style={{ marginTop: 30, fontFamily: MONO, fontSize: 72, color: GREEN, fontWeight: 600, textShadow: `0 0 24px ${GREEN}aa` }}>lokaah talky</div>
        <div style={{ marginTop: 16, fontFamily: MONO, fontSize: 26, color: "#9affa0" }}>github.com/venkat-lokaah/lokaah-talky</div>
      </div>
    </Scene>
  );
};

export const Explainer: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: BG }}>
      <AbsoluteFill style={{ background: `radial-gradient(circle at 50% 42%, ${GREEN}10, transparent 60%)` }} />
      <Sequence from={0} durationInFrames={80}><Title /></Sequence>
      <Sequence from={80} durationInFrames={150}><WhatIs /></Sequence>
      <Sequence from={230} durationInFrames={250}><Install /></Sequence>
      <Sequence from={480} durationInFrames={180}><HowToUse /></Sequence>
      <Sequence from={660} durationInFrames={120}><Features /></Sequence>
      <Sequence from={780} durationInFrames={90}><EndCard /></Sequence>
    </AbsoluteFill>
  );
};
