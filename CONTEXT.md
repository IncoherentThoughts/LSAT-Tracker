# LSAT Tracker — Domain Glossary

The language of the project. Terms here are canonical; code and docs should use them.

## Clock

The single running stopwatch for one Study Day. Exactly one Clock exists per
user, shared across every device signed into the same Account. Any device can
start or pause the Clock, and every signed-in device eventually shows the same
state. Starting a Clock that is already running is a no-op.

## Clock State

Everything needed to reproduce the Clock on any device: whether it is
running, when the current run began, which Study Day it belongs to, and the
seconds already banked for that Study Day. Represented in code as
`ClockSnapshot`.

## Clock Action

A timestamped change to the Clock State made on one device: start, pause, a
Manual Edit, a Daily Goal change, a reset, or a Rollover. When two devices act
on the Clock without having seen each other's most recent action, the later
Clock Action wins outright. Every Clock Action banks the time elapsed before
it, so a losing action can never erase minutes another device has already
counted.

## Study Day

The unit the daily timer counts. Runs from 4:00 AM to 4:00 AM local time, not
midnight. A Study Day is named by the calendar date it began on.

## Rollover

The transition from one Study Day to the next at 4:00 AM. The departing Study
Day's time becomes a Session; the daily counter starts again at zero. A
running Clock keeps running across a Rollover. Rollover is idempotent: any
number of devices can perform it independently and they all arrive at the
same result, so there is no coordination needed over who does it first.

## Session

The record of one Study Day: its date and total seconds. There is at most one
Session per Study Day per Account. Sessions are the history the Statistics
screen reads, and they are what the All-Time Total is derived from.

## Manual Edit

A user-entered override of a Session's total for a given date. A Manual Edit
is a Clock Action like any other and follows the same last-action-wins rule
when two devices edit the same Study Day differently.

## Account

The email identity that owns one shared Clock and its Sessions. Every device
signs into the same Account once (email and password); Clock Actions and
Sessions sync between devices signed into the same Account.
