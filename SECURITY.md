# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/hakushi/security/advisories/new).

Say what an attacker can do, and how: the canvas, the event or the
change, and the steps or the payload. We answer within a week, agree on a
fix and a date, and credit you in the advisory unless you ask us not to.

## Supported versions

Security fixes are made to the latest release. Hakushi is before 1.0, so a
fix is not backported to an earlier minor version.

## What is in scope

Hakushi applies changes in your LiveView, and in a room shared by the
people of a canvas, on events from the browser, which any person can
craft. A problem is in scope when such an event can:

- make a change that the canvas's rules, `readonly` or `on_change`
  refuse, or one that `on_change` does not see;
- move, resize or delete a locked node;
- put data of its own into a node: the data of a node comes from the
  server (the graph, `new_node`, a copy of the server's own nodes), never
  from the browser;
- reach the canvas, the changes or the cursors of another topic, or
  undo another person's change;
- put HTML or script into the page through a label, a name or a message;
- crash the LiveView or the room, or make the server do unbounded work.

Who may open a canvas, and its topic, is the app's: a topic that a
person can guess is shared with them when the LiveView mounts it. Check
the person in the LiveView's `mount`, and give each canvas a topic of its
record (see the [Collaboration](guides/collaboration.md) guide).
