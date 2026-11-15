import { Html, Line, OrbitControls } from "@react-three/drei";
import { Canvas, useFrame, useThree, type ThreeEvent } from "@react-three/fiber";
import { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import type { Landmark, Pt, Route, Terrain } from "./engine";

/* Immersive 3D terrain built from the real USGS HiRISE DTM window (see data/build_dem.py).
   Colour, rocks, sky and dust are procedural visual treatment; only the shape is measured/derived. */

export type Meta = { w: number; h: number; cellM: number; widthM: number; heightM: number; min: number; max: number; hiW: number; hiH: number };
export type View3D = "natural" | "slope" | "contours" | "pressure";
export type Cam = "orbit" | "walk";
export type Probe = { fx: number; fy: number };
const hex = (h: string) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const lerp3 = (stops: string[], t: number) => { const n = stops.length - 1, x = Math.min(1, Math.max(0, t)) * n, i = Math.min(n - 1, Math.floor(x)), f = x - i, a = hex(stops[i]), b = hex(stops[i + 1]); return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]; };
const GROUND = ["#5e3b2e", "#7d513b", "#9c6a48", "#b88a62", "#cfa77f"];
const SLOPE_RAMP = ["#3b332e", "#6b5848", "#b85c43", "#f1d9bd"];
const PRESS_RAMP = ["#2a2f3d", "#46697a", "#789ba8", "#dbe8ec"];
const SCALE_H = 11100;

function noiseTable() { let s = 12345; const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; return Float32Array.from({ length: 256 * 256 }, r); }
const NT = noiseTable();
const vnoise = (x: number, y: number) => { const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf); const g = (a: number, b: number) => NT[((b & 255) << 8) | (a & 255)]; return (g(xi, yi) * (1 - u) + g(xi + 1, yi) * u) * (1 - v) + (g(xi, yi + 1) * (1 - u) + g(xi + 1, yi + 1) * u) * v; };

export function makeHeights(buf: ArrayBuffer, meta: Meta) { const i16 = new Int16Array(buf), out = new Float32Array(i16.length); for (let i = 0; i < i16.length; i++) out[i] = i16[i] / 10; return out; }
const sampleH = (hi: Float32Array, m: Meta, fx: number, fy: number) => {
  const x = Math.min(m.hiW - 1.001, Math.max(0, fx * (m.hiW - 1))), y = Math.min(m.hiH - 1.001, Math.max(0, fy * (m.hiH - 1))), xi = Math.floor(x), yi = Math.floor(y), tx = x - xi, ty = y - yi, i = yi * m.hiW + xi;
  return (hi[i] * (1 - tx) + hi[i + 1] * tx) * (1 - ty) + (hi[i + m.hiW] * (1 - tx) + hi[i + m.hiW + 1] * tx) * ty;
};

function buildAlbedo(hi: Float32Array, m: Meta, view: View3D) {
  const TW = 1600, TH = Math.round((TW * m.hiH) / m.hiW), c = document.createElement("canvas"); c.width = TW; c.height = TH;
  const ctx = c.getContext("2d")!, img = ctx.createImageData(TW, TH);
  const loP = Math.exp(-(m.max - m.min) / SCALE_H);
  for (let y = 0; y < TH; y++) for (let x = 0; x < TW; x++) {
    const fx = x / (TW - 1), fy = y / (TH - 1), e = sampleH(hi, m, fx, fy);
    const dx = (sampleH(hi, m, fx + 1 / TW, fy) - sampleH(hi, m, fx - 1 / TW, fy)) / ((2 * m.widthM) / TW), dz = (sampleH(hi, m, fx, fy + 1 / TH) - sampleH(hi, m, fx, fy - 1 / TH)) / ((2 * m.heightM) / TH);
    const slope = Math.atan(Math.hypot(dx, dz)) * 57.2958, wx = fx * m.widthM, wy = fy * m.heightM;
    const n = 0.5 * vnoise(wx / 40, wy / 40) + 0.3 * vnoise(wx / 9, wy / 9) + 0.2 * vnoise(wx / 2.2, wy / 2.2); // regolith detail
    const et = (e - m.min) / (m.max - m.min);
    let [r, g, b] = lerp3(GROUND, et * 0.8 + (n - 0.5) * 0.5);
    const rock = Math.min(1, slope / 28); r = r * (1 - rock * 0.45) + 70 * rock * 0.45; g = g * (1 - rock * 0.45) + 58 * rock * 0.45; b = b * (1 - rock * 0.45) + 52 * rock * 0.45;
    const k = 0.84 + n * 0.32; r *= k; g *= k; b *= k * 0.97;
    if (view === "slope") { const q = lerp3(SLOPE_RAMP, Math.min(1, slope / 25)); r = r * 0.25 + q[0] * 0.75; g = g * 0.25 + q[1] * 0.75; b = b * 0.25 + q[2] * 0.75; }
    else if (view === "pressure") { const t = (Math.exp(-(e - m.min) / SCALE_H) - loP) / (1 - loP), q = lerp3(PRESS_RAMP, t); r = r * 0.3 + q[0] * 0.7; g = g * 0.3 + q[1] * 0.7; b = b * 0.3 + q[2] * 0.7; }
    else if (view === "contours") { const ev = (xx: number, yy: number) => Math.floor(sampleH(hi, m, xx, yy) / 10), b0 = ev(fx, fy); if (b0 !== ev(fx + 1.2 / TW, fy) || b0 !== ev(fx, fy + 1.2 / TH)) { const major = b0 % 5 === 0; r = major ? 250 : 232; g = major ? 240 : 205; b = major ? 220 : 160; } }
    const o = (y * TW + x) * 4; img.data[o] = r; img.data[o + 1] = g; img.data[o + 2] = b; img.data[o + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; t.needsUpdate = true; return t;
}

function Sky({ sunDir }: { sunDir: THREE.Vector3 }) {
  const mat = useMemo(() => new THREE.ShaderMaterial({ side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { sun: { value: new THREE.Vector3() } },
    vertexShader: "varying vec3 d; void main(){ d = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
    fragmentShader: "varying vec3 d; uniform vec3 sun; void main(){ float h = clamp(d.y,0.0,1.0); vec3 hor = vec3(0.86,0.64,0.47); vec3 mid = vec3(0.62,0.47,0.40); vec3 top = vec3(0.30,0.26,0.30); vec3 c = mix(hor, mid, smoothstep(0.0,0.25,h)); c = mix(c, top, smoothstep(0.2,0.9,h)); float s = max(dot(d, normalize(sun)),0.0); c += vec3(0.45,0.55,0.70)*pow(s,24.0)*0.55 + vec3(1.0,0.93,0.82)*pow(s,900.0); if(d.y<0.0) c = hor*0.85; gl_FragColor = vec4(c,1.0); }" }), []);
  useEffect(() => { mat.uniforms.sun.value.copy(sunDir); }, [mat, sunDir]);
  return <mesh renderOrder={-1}><sphereGeometry args={[18000, 32, 16]} /><primitive object={mat} attach="material" /></mesh>;
}

function Dust({ follow }: { follow: React.MutableRefObject<THREE.Vector3> }) {
  const isMobile = typeof window !== "undefined" && window.innerWidth < 768;
  const N = isMobile ? 180 : 800, ref = useRef<THREE.Points>(null);
  const skip = useRef(0);
  const pos = useMemo(() => { const a = new Float32Array(N * 3); for (let i = 0; i < N; i++) { a[i * 3] = (Math.random() - 0.5) * 900; a[i * 3 + 1] = Math.random() * 90; a[i * 3 + 2] = (Math.random() - 0.5) * 900; } return a; }, [N]);
  useFrame(({ clock }, dt) => {
    const p = ref.current; if (!p) return;
    if (isMobile && (++skip.current % 2 !== 0)) return; // throttle particle update on mobile
    const t = clock.elapsedTime, a = p.geometry.attributes.position as THREE.BufferAttribute;
    const factor = isMobile ? dt * 2 : dt;
    for (let i = 0; i < N; i++) { let x = a.getX(i) + factor * (6 + Math.sin(t * 0.3 + i) * 2), z = a.getZ(i) + factor * 2; if (x > 450) x -= 900; if (z > 450) z -= 900; a.setXYZ(i, x, a.getY(i) + Math.sin(t + i) * factor * 0.8, z); }
    a.needsUpdate = true; p.position.set(follow.current.x, follow.current.y - 5, follow.current.z);
  });
  return <points ref={ref} frustumCulled={false}><bufferGeometry><bufferAttribute attach="attributes-position" args={[pos, 3]} /></bufferGeometry><pointsMaterial color="#e3b48a" size={0.7} sizeAttenuation transparent opacity={0.3} depthWrite={false} /></points>;
}

type SceneProps = { hi: Float32Array; meta: Meta; T: Terrain; view: View3D; exag: number; sunEl: number; sunAz: number; cam: Cam; playing: boolean; speed: number; route: Route | null; landmarks: Landmark[]; step: number; onReach: (i: number) => void; onProbe: (p: Probe) => void; resetKey: number };

function Scene(p: SceneProps) {
  const { hi, meta: m } = p, { camera, scene } = useThree();
  const albedo = useMemo(() => buildAlbedo(hi, m, p.view), [hi, m, p.view]);
  const geo = useMemo(() => {
    const g = new THREE.PlaneGeometry(m.widthM, m.heightM, m.hiW - 1, m.hiH - 1); g.rotateX(-Math.PI / 2);
    const a = g.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < a.count; i++) a.setY(i, hi[i] - m.min);
    g.computeVertexNormals(); return g;
  }, [hi, m]);
  const skirt = useMemo(() => { // dark side walls so the window reads as a solid block
    const pos: number[] = [], W_ = m.hiW, H_ = m.hiH, X = (i: number) => (i / (W_ - 1) - 0.5) * m.widthM, Z = (j: number) => (j / (H_ - 1) - 0.5) * m.heightM, base = -60;
    const edge = (pts: [number, number, number][]) => { for (let k = 0; k < pts.length - 1; k++) { const [a, b] = [pts[k], pts[k + 1]]; pos.push(a[0], a[1], a[2], a[0], base, a[2], b[0], b[1], b[2], b[0], b[1], b[2], a[0], base, a[2], b[0], base, b[2]); } };
    const H = (i: number, j: number) => hi[j * W_ + i] - m.min;
    edge(Array.from({ length: W_ }, (_, i) => [X(i), H(i, 0), Z(0)] as [number, number, number]));
    edge(Array.from({ length: W_ }, (_, i) => [X(i), H(i, H_ - 1), Z(H_ - 1)] as [number, number, number]));
    edge(Array.from({ length: H_ }, (_, j) => [X(0), H(0, j), Z(j)] as [number, number, number]));
    edge(Array.from({ length: H_ }, (_, j) => [X(W_ - 1), H(W_ - 1, j), Z(j)] as [number, number, number]));
    const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3)); g.computeVertexNormals(); return g;
  }, [hi, m]);
  const yAt = (fx: number, fy: number, extra = 0) => (sampleH(hi, m, fx, fy) - m.min) * p.exag + extra;
  const toW = (q: Pt, extra = 0): [number, number, number] => { const fx = q.x / (m.w - 1), fy = q.y / (m.h - 1); return [(fx - 0.5) * m.widthM, yAt(fx, fy, extra), (fy - 0.5) * m.heightM]; };
  const sunDir = useMemo(() => { const el = (p.sunEl * Math.PI) / 180, az = (p.sunAz * Math.PI) / 180; return new THREE.Vector3(Math.cos(el) * Math.sin(az), Math.sin(el), -Math.cos(el) * Math.cos(az)); }, [p.sunEl, p.sunAz]);
  const light = useRef<THREE.DirectionalLight>(null), follow = useRef(new THREE.Vector3()), orbit = useRef<any>(null);
  const walk = p.cam === "walk" && !!p.route;
  scene.fog = new THREE.Fog("#c79a74", walk ? 250 : 1800, walk ? 3800 : 14000);
  scene.background = new THREE.Color("#c79a74");

  const isMobile = typeof window !== "undefined" && window.innerWidth < 768;
  const rocks = useMemo(() => { // scattered boulders on gentle ground (visual only)
    const N = isMobile ? 500 : 2200, mesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(1, 1), new THREE.MeshStandardMaterial({ color: "#7a5a48", roughness: 1, flatShading: true }), N), d = new THREE.Object3D(), col = new THREE.Color();
    let s = 99; const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
    for (let i = 0; i < N; i++) {
      const fx = 0.03 + r() * 0.94, fy = 0.03 + r() * 0.94, size = 0.25 + Math.pow(r(), 3) * 2.2;
      d.position.set((fx - 0.5) * m.widthM, yAt(fx, fy, size * 0.25), (fy - 0.5) * m.heightM); d.rotation.set(r() * 6, r() * 6, r() * 6); d.scale.set(size * (0.8 + r() * 0.6), size * (0.5 + r() * 0.4), size * (0.8 + r() * 0.6)); d.updateMatrix();
      mesh.setMatrixAt(i, d.matrix); mesh.setColorAt(i, col.setHSL(0.05 + r() * 0.03, 0.3, 0.18 + r() * 0.2));
    }
    mesh.castShadow = !isMobile; mesh.receiveShadow = !isMobile; return mesh;
  }, [hi, m, p.exag, isMobile]); // eslint-disable-line react-hooks/exhaustive-deps

  const path = p.route?.path ?? [];
  const routePts = useMemo(() => path.map((q) => new THREE.Vector3(...toW(q, 1.4))), [path, p.exag, hi]); // eslint-disable-line react-hooks/exhaustive-deps
  const prog = useRef(0), hold = useRef(0), yaw = useRef(0), drag = useRef<{ x: number } | null>(null), lastReach = useRef(-1), snap = useRef(true);

  useEffect(() => { // camera presets
    if (p.cam === "orbit") { camera.position.set(m.widthM * 0.12, m.widthM * 0.5, m.heightM * 1.25); camera.lookAt(0, 0, 0); orbit.current?.target.set(0, 0, 0); orbit.current?.update(); }
    else if (p.route) { prog.current = p.landmarks[p.step]?.idx ?? 0; lastReach.current = -1; yaw.current = 0; snap.current = true; }
  }, [p.cam, p.resetKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (walk && p.landmarks[p.step]) { prog.current = p.landmarks[p.step].idx; hold.current = 0; snap.current = true; } }, [p.step]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!walk) return; const el = document.getElementById("t3d-canvas") as HTMLElement | null; if (!el) return;
    const dn = (e: PointerEvent) => { drag.current = { x: e.clientX }; }, mv = (e: PointerEvent) => { if (drag.current) { yaw.current -= (e.clientX - drag.current.x) * 0.006; drag.current.x = e.clientX; } }, up = () => { drag.current = null; };
    el.addEventListener("pointerdown", dn); window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
    return () => { el.removeEventListener("pointerdown", dn); window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
  }, [walk]);

  useFrame((_, dt) => {
    if (light.current) { light.current.position.copy(sunDir).multiplyScalar(4000); light.current.target.position.set(follow.current.x, 0, follow.current.z); light.current.target.updateMatrixWorld(); }
    if (!walk) { follow.current.copy(camera.position); follow.current.y = 0; return; }
    const n = path.length;
    if (p.playing && hold.current <= 0) { prog.current = Math.min(n - 1, prog.current + (p.speed / m.cellM) * dt); }
    hold.current -= dt;
    const i = Math.floor(prog.current), f = prog.current - i, a = routePts[Math.min(n - 1, i)], b = routePts[Math.min(n - 1, i + 1)];
    const pos = a.clone().lerp(b, f);
    const la = routePts[Math.min(n - 1, i + 4)], lb = routePts[Math.max(0, i - 1)];
    const hd = Math.atan2(la.x - lb.x, -(la.z - lb.z)) || 0; // heading from path
    const fx = pos.x / m.widthM + 0.5, fy = pos.z / m.heightM + 0.5, eye = yAt(fx, fy) + 1.75;
    if (snap.current) { camera.position.set(pos.x, eye, pos.z); snap.current = false; } else camera.position.lerp(new THREE.Vector3(pos.x, eye, pos.z), 0.25);
    const ang = hd + yaw.current; camera.lookAt(camera.position.x + Math.sin(ang) * 60, camera.position.y - 1.2, camera.position.z - Math.cos(ang) * 60);
    follow.current.copy(camera.position);
    const lm = p.landmarks.findIndex((l) => Math.abs(l.idx - prog.current) < 0.35);
    if (lm >= 0 && lm !== lastReach.current && p.playing) { lastReach.current = lm; hold.current = 2.2; p.onReach(lm); }
  });

  return (
    <>
      <Sky sunDir={sunDir} />
      <ambientLight intensity={0.55} color="#e8c8aa" />
      <hemisphereLight args={["#d9b08c", "#6b4636", 0.45]} />
      <directionalLight ref={light} intensity={3.1} color="#fff0dc" castShadow={!isMobile} shadow-mapSize={isMobile ? [1024, 1024] : [2048, 2048]} shadow-bias={-0.0004} shadow-normalBias={0.6}>
        <orthographicCamera attach="shadow-camera" args={[-2600, 2600, 2600, -2600, 100, 9000]} />
      </directionalLight>
      <mesh geometry={geo} scale={[1, p.exag, 1]} receiveShadow castShadow onClick={(e: ThreeEvent<MouseEvent>) => { e.stopPropagation(); p.onProbe({ fx: e.point.x / m.widthM + 0.5, fy: e.point.z / m.heightM + 0.5 }); }}>
        <meshStandardMaterial map={albedo} roughness={0.96} metalness={0} />
      </mesh>
      <mesh geometry={skirt} scale={[1, p.exag, 1]}><meshBasicMaterial color="#3a2a22" side={THREE.DoubleSide} /></mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -0.6, 0]}><planeGeometry args={[60000, 60000]} /><meshStandardMaterial color="#7d513b" roughness={1} /></mesh>
      <primitive object={rocks} />
      <Dust follow={follow} />
      {routePts.length > 1 && <Line points={routePts} color="#D3A24C" lineWidth={3.2} />}
      {p.landmarks.map((l, k) => { const [x, y, z] = toW(l.pt), on = k === p.step; return (
        <group key={l.n} position={[x, y, z]}>
          <mesh position={[0, 14, 0]}><cylinderGeometry args={[0.35, 0.35, 28, 8]} /><meshBasicMaterial color={on ? "#B85C43" : "#241b17"} /></mesh>
          <mesh position={[0, 29, 0]}><sphereGeometry args={[on ? 2.2 : 1.5, 12, 8]} /><meshBasicMaterial color={on ? "#f5c26b" : "#f5f1e8"} /></mesh>
          <Html position={[0, 36, 0]} center distanceFactor={1100} zIndexRange={[10, 0]} style={{ pointerEvents: "none" }}><div style={{ fontFamily: "IBM Plex Mono", fontSize: 11, whiteSpace: "nowrap", padding: "2px 6px", background: on ? "#B85C43" : "rgba(36,27,23,.85)", color: "#f5f1e8", borderRadius: 2 }}>{l.n} · {l.name}</div></Html>
        </group>); })}
      {!walk && <OrbitControls ref={orbit} makeDefault target={[0, 0, 0]} maxPolarAngle={Math.PI / 2 - 0.03} minDistance={25} maxDistance={7000} enableDamping dampingFactor={0.08} />}
    </>
  );
}

export default function Terrain3D(props: Omit<SceneProps, "hi" | "meta"> & { meta: Meta; onReady?: () => void }) {
  const [hi, setHi] = useState<Float32Array | null>(null), [err, setErr] = useState("");
  const isMobile = typeof window !== "undefined" && window.innerWidth < 768;
  useEffect(() => { fetch(`${import.meta.env.BASE_URL}jezero-dem.bin`).then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.arrayBuffer(); }).then((b) => setHi(makeHeights(b, props.meta))).catch((e) => setErr(String(e))); }, [props.meta]);
  useEffect(() => { if (hi) props.onReady?.(); }, [hi]); // eslint-disable-line react-hooks/exhaustive-deps
  if (err) return <div role="alert" className="absolute inset-0 flex items-center justify-center font-mono text-[12px] text-ink bg-map">Could not load terrain data ({err}).</div>;
  if (!hi) return <div role="status" className="absolute inset-0 flex items-center justify-center font-mono text-[12px] tracking-[0.08em] text-ink/85 bg-map">Loading HiRISE terrain model…</div>;
  return (
    <Canvas id="t3d-canvas" shadows={isMobile ? false : "percentage"} dpr={isMobile ? [1, 1.25] : [1, 1.75]} camera={{ fov: 52, near: 0.5, far: 40000, position: [500, 2200, 3400] }} gl={{ antialias: !isMobile, powerPreference: "high-performance", toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1.05 }}>
      <Scene {...props} hi={hi} />
    </Canvas>
  );
}
