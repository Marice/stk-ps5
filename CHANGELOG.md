# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow
the title's `contentVersion` in `sce_sys/param.json`.

## [Unreleased]

## [00.001.000] - 2026-10-12

First alpha test build of SuperTuxKart 1.5 as a native PS5 title.

### Added
- Native title `PPSA69421`, rendering through the PS5 OpenGL SDK (EGL,
  OpenGL 4.6 Core) at 1920x1080, with dynamic lighting.
- DualSense support with a racing-game layout: Cross accelerates, Square
  brakes, Circle uses an item, Triangle looks back, L1 is nitro, R1 drifts,
  the touchpad rescues the kart. Cross confirms and Circle goes back in menus.
- SuperTuxKart's on-screen keyboard for text input, and a first player named
  after the PS5 account.
- Home screen icon and background.
- `stk.log` in the title folder, with frame rate and memory every 5 s.

### Known issues
- Network play is switched off: the online code's start-up ends the process.
- The options screen can crash after some navigation; graphics and sound
  settings are fixed for now.
- The first load of a track is slow.
