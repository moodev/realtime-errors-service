// This script basically just exists to make process management simpler.
// `node index.js` is a simple service as far as systemd is concerned, for example.

// This is simpler than composing an external pipeline to insert timestamps.
// It's also easier/lazier than introducing a whole logging framework, and pretty much good enough!
//
require('console-stamp')(console, {
  pattern: 'isoUtcDateTime'
});


// Doing the following is easier than using the 'lsc' command line tool (and equivalent!)
// As you launch node directly, rather than lsc starting it as a child in some weird way:
//   - the process tree makes more sense
//   - daemonization is trivial
//   - you can use the native 'cluster' module instead of forever or other overcomplications, if you want
//
require('livescript');
require('./app/app');
