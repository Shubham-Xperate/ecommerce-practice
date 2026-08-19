// Runtime configuration for the Angular app.
//
// This file is intentionally NOT processed by the Angular/TypeScript build -
// it is a plain script copied as-is into the output and loaded via a
// <script> tag in index.html BEFORE the Angular bundle runs (see the
// comment there for why ordering matters).
//
// The value below ('/api') is the default used for local `ng serve`
// development, where nginx isn't in front of the app. In built Docker
// containers, this exact file gets overwritten at container startup by
// docker-entrypoint.sh, which regenerates it from the API_URL environment
// variable - so the same compiled app can point at different backend URLs
// in different environments without recompiling anything.
window.__env = {
  apiUrl: '/api'
};
