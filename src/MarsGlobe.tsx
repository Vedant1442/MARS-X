import { useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { Html, OrbitControls, useTexture } from "@react-three/drei";
import * as THREE from "three";

export type GlobeApi = { zoom: (factor: number) => void };
export type FlyTarget = { lat: number; lon: number; dist?: number } | null;

const R = 1;

/** Equirectangular lat/lon (deg, east positive) to a point on the SphereGeometry surface. */
export function latLon(lat: number, lon: number, r = R) {
  const la = (lat * Math.PI) / 180;
  const phi = ((lon + 180) * Math.PI) / 180;
  return new THREE.Vector3(-Math.cos(phi) * Math.cos(la) * r, Math.sin(la) * r, Math.sin(phi) * Math.cos(la) * r);
}

// Landing-site coordinates are published mission values. Region boxes are approximate outlines.
const SITES = [
  { id: "JEZERO", lat: 18.38, lon: 77.58, kind: "rover" },
  { id: "GALE", lat: -5.4, lon: 137.8, kind: "rover" },
  { id: "VALLES MARINERIS", lat: -13.9, lon: -59.2, kind: "feature" },
  { id: "OLYMPUS MONS", lat: 18.65, lon: -133.8, kind: "feature" },
] as const;

const REGIONS: [number, number, number, number][] = [
  [14, 24, 72, 83], // Jezero region
  [-10, -1, 133, 143], // Gale region
  [-18, -6, -95, -45], // Valles Marineris region
];

function usePolyline(points: THREE.Vector3[], color: string, opacity: number) {
  const line = useMemo(() => {
    const g = new THREE.BufferGeometry().setFromPoints(points);
    const m = new THREE.LineBasicMaterial({ color, transparent: true, opacity, depthWrite: false });
    return new THREE.Line(g, m);
  }, [points, color, opacity]);
  useEffect(() => () => { line.geometry.dispose(); (line.material as THREE.Material).dispose(); }, [line]);
  return line;
}

function Graticule() {
  const obj = useMemo(() => {
    const pts: THREE.Vector3[] = [];
    const seg = (a: THREE.Vector3, b: THREE.Vector3) => { pts.push(a, b); };
    for (let lat = -60; lat <= 60; lat += 30) for (let lon = -180; lon < 180; lon += 6) seg(latLon(lat, lon, 1.002), latLon(lat, lon + 6, 1.002));
    for (let lon = -180; lon < 180; lon += 30) for (let lat = -84; lat < 84; lat += 6) seg(latLon(lat, lon, 1.002), latLon(lat + 6, lon, 1.002));
    const g = new THREE.BufferGeometry().setFromPoints(pts);
    const m = new THREE.LineBasicMaterial({ color: "#f5f1e8", transparent: true, opacity: 0.22, depthWrite: false });
    return new THREE.LineSegments(g, m);
  }, []);
  useEffect(() => () => { obj.geometry.dispose(); (obj.material as THREE.Material).dispose(); }, [obj]);
  return <primitive object={obj} />;
}

function Region({ box }: { box: [number, number, number, number] }) {
  const pts = useMemo(() => {
    const [a, b, c, d] = box; const p: THREE.Vector3[] = [];
    for (let lon = c; lon <= d; lon += 1) p.push(latLon(a, lon, 1.004));
    for (let lat = a; lat <= b; lat += 1) p.push(latLon(lat, d, 1.004));
    for (let lon = d; lon >= c; lon -= 1) p.push(latLon(b, lon, 1.004));
    for (let lat = b; lat >= a; lat -= 1) p.push(latLon(lat, c, 1.004));
    return p;
  }, [box]);
  return <primitive object={usePolyline(pts, "#d3a24c", 0.95)} />;
}

/** One illustrative trajectory (not a real traverse), drawn progressively on a loop. */
function Trajectory({ reduce }: { reduce: boolean }) {
  const a = useMemo(() => latLon(18.38, 77.58).normalize(), []);
  const b = useMemo(() => latLon(-5.4, 137.8).normalize(), []);
  const pts = useMemo(() => {
    const q = new THREE.Quaternion().setFromUnitVectors(a, b); const out: THREE.Vector3[] = [];
    for (let i = 0; i <= 80; i++) { const t = i / 80; out.push(a.clone().applyQuaternion(new THREE.Quaternion().slerp(q, t)).multiplyScalar(1.006 + 0.035 * Math.sin(Math.PI * t))); }
    return out;
  }, [a, b]);
  const line = usePolyline(pts, "#f5f1e8", 0.9);
  const head = useRef<THREE.Mesh>(null);
  useFrame(({ clock }) => {
    const total = pts.length;
    const t = reduce ? 1 : Math.min(1, (clock.elapsedTime % 9) / 6);
    const n = Math.max(2, Math.floor(t * total));
    line.geometry.setDrawRange(0, n);
    if (head.current) { head.current.position.copy(pts[n - 1]); head.current.visible = !reduce && t < 1; }
  });
  return (<>
    <primitive object={line} />
    <mesh ref={head}><sphereGeometry args={[0.009, 12, 8]} /><meshBasicMaterial color="#f5f1e8" /></mesh>
  </>);
}

function Atmosphere() {
  const mat = useMemo(() => new THREE.ShaderMaterial({
    side: THREE.BackSide, transparent: true, depthWrite: false,
    vertexShader: "varying vec3 vN; void main(){ vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
    fragmentShader: "varying vec3 vN; void main(){ float a = smoothstep(0.0, 0.48, -vN.z); a = pow(a, 1.8) * 0.65; gl_FragColor = vec4(0.92, 0.48, 0.30, a); }",
  }), []);
  useEffect(() => () => mat.dispose(), [mat]);
  return <mesh scale={1.12}><sphereGeometry args={[1, 48, 32]} /><primitive object={mat} attach="material" /></mesh>;
}

function Planet({ reduce, onReady, planetRef }: { reduce: boolean; onReady: () => void; planetRef: React.RefObject<THREE.Mesh | null> }) {
  const tex = useTexture(`${import.meta.env.BASE_URL}mars-color-2k.jpg`);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;

  useEffect(() => {
    onReady();
  }, [onReady]);

  return (<>
    <mesh ref={planetRef}>
      <sphereGeometry args={[R, 96, 64]} />
      <meshStandardMaterial map={tex} roughness={0.88} metalness={0.02} />
    </mesh>
    <Graticule />
    {REGIONS.map((b, i) => <Region key={i} box={b} />)}
    <Trajectory reduce={reduce} />
    {SITES.map((s) => {
      const p = latLon(s.lat, s.lon, 1.006);
      return (
        <group key={s.id}>
          <mesh position={p}><sphereGeometry args={[s.kind === "rover" ? 0.013 : 0.009, 14, 10]} /><meshBasicMaterial color={s.kind === "rover" ? "#d3a24c" : "#f5f1e8"} /></mesh>
          <Html position={latLon(s.lat, s.lon, 1.02)} occlude={[planetRef as React.RefObject<THREE.Object3D>]} zIndexRange={[10, 0]} style={{ pointerEvents: "none" }}>
            <span className="block -translate-y-1/2 translate-x-2 whitespace-nowrap font-mono text-[9px] tracking-[0.14em] text-[#f5f1e8] [text-shadow:0_0_3px_rgb(36,27,23,0.9),0_0_6px_rgb(36,27,23,0.6)]">{s.id}</span>
          </Html>
        </group>
      );
    })}
  </>);
}

function Rig({ fly, controls, api, reduce }: { fly: FlyTarget; controls: React.RefObject<any>; api: React.RefObject<GlobeApi | null>; reduce: boolean }) {
  const { camera, invalidate } = useThree();
  const st = useRef<{ t0: number; a: THREE.Vector3; d0: number; q: THREE.Quaternion; d1: number } | null>(null);
  useEffect(() => {
    api.current = { zoom: (f) => { camera.position.setLength(THREE.MathUtils.clamp(camera.position.length() * f, 1.3, 4.5)); invalidate(); } };
  }, [camera, invalidate, api]);
  useEffect(() => {
    if (!fly) return;
    const a = camera.position.clone(); const d0 = a.length(); a.normalize();
    const b = latLon(fly.lat, fly.lon).normalize();
    st.current = { t0: performance.now(), a, d0, q: new THREE.Quaternion().setFromUnitVectors(a, b), d1: fly.dist ?? 1.42 };
    if (controls.current) { controls.current.autoRotate = false; controls.current.enabled = false; }
  }, [fly, camera, controls]);
  useFrame(() => {
    const s = st.current; if (!s) return;
    const k = reduce ? 1 : Math.min(1, (performance.now() - s.t0) / 2000);
    const e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
    const dir = s.a.clone().applyQuaternion(new THREE.Quaternion().slerp(s.q, e));
    camera.position.copy(dir.multiplyScalar(THREE.MathUtils.lerp(s.d0, s.d1, e)));
    camera.lookAt(0, 0, 0);
    if (k >= 1) st.current = null;
  });
  return null;
}

export default function MarsGlobe({ active, reduce, fly, apiRef, onReady, compact }: { active: boolean; reduce: boolean; fly: FlyTarget; apiRef: React.RefObject<GlobeApi | null>; onReady: () => void; compact: boolean }) {
  const controls = useRef<any>(null);
  const planet = useRef<THREE.Mesh>(null);
  const [engaged, setEngaged] = useState(false);
  return (
    <Canvas
      frameloop={!active ? "never" : reduce ? "demand" : "always"}
      dpr={[1, compact ? 1.5 : 2]}
      camera={{ position: latLon(10, -20).setLength(3.1).toArray(), fov: 34, near: 0.1, far: 20 }}
      gl={{ antialias: true, alpha: true, powerPreference: "high-performance", toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1.05 }}
      onPointerDown={() => setEngaged(true)}
      onPointerLeave={() => setEngaged(false)}
      aria-label="Interactive 3D globe of Mars. Drag to rotate; use the zoom buttons or focus the globe and scroll to zoom."
      role="img"
    >
      <ambientLight intensity={0.55} color="#ffd4c0" />
      <directionalLight position={[-4, 2.5, 4.5]} intensity={1.85} color="#fff6ee" />
      <directionalLight position={[4, -1, -3]} intensity={0.35} color="#b85230" />
      <Planet reduce={reduce} onReady={onReady} planetRef={planet} />
      <Atmosphere />
      <Rig fly={fly} controls={controls} api={apiRef} reduce={reduce} />
      <OrbitControls ref={controls} enablePan={false} enableDamping dampingFactor={0.08} rotateSpeed={0.5} zoomSpeed={0.6} enableZoom={engaged} minDistance={1.3} maxDistance={4.5} autoRotate={!reduce} autoRotateSpeed={0.35} />
    </Canvas>
  );
}
