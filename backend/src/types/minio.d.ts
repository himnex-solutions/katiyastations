// The `minio` package's CommonJS entry point ships no top-level `types`
// field usable under TS's classic module resolution (only the ESM build
// does). Declaring it here avoids forcing project-wide moduleResolution
// changes just for one dependency.
declare module 'minio';
