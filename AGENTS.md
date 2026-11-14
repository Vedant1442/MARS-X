# MARS-X

React + Vite + Tailwind CSS project for Mars surface exploration planning.

## Development Server

Start with `pnpm dev`. The Vite dev server runs on port 8443 by default.

## Project Structure

- `src/main.tsx` - React entrypoint; imports `src/index.css` and mounts `src/App.tsx`
- `src/App.tsx` - Primary application component
- `src/engine.ts` - Routing engine (A*, risk scoring, landmarks)
- `src/jezeroGrid.ts` - HiRISE DTM terrain data (generated)
- `src/MarsGlobe.tsx` - 3D Mars globe (React Three Fiber)
- `src/Terrain3D.tsx` - Immersive 3D terrain view
- `src/index.css` - Global CSS and Tailwind CSS v4 import
- `index.html` - Vite HTML shell
- `backend/` - FastAPI backend for server-side routing
- `data/` - NASA dataset pipeline scripts

## Dependencies

- Runtime: React 19, React DOM 19, Three.js, React Three Fiber
- Styling: Tailwind CSS v4 with `@tailwindcss/vite`
- Build: Vite 8, TypeScript 5.7, `@vitejs/plugin-react`
- Backend: FastAPI, uvicorn, pydantic

## Code quality

- Use double quotes for strings containing apostrophes.
- Ensure JSX tags are closed and braces are balanced.
- Export components as default exports.
