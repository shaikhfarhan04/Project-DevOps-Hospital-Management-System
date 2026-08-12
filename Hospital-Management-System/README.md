# Unity Hospital — Modern UI

A fully modernized, static multi-page hospital website built with **pure HTML, CSS, and vanilla JavaScript**. No frameworks, no build step — just open `index.html`.

**Live:** https://nirravv.github.io/Hospital-Management-Html/

## Features

- Dark-first design with a persisted light-mode toggle
- Animated aurora background, cursor-follow glow, and scroll-reveal transitions
- Glassmorphism cards, gradient typography, bento-grid specialities
- Animated counters, hover-reveal doctor socials, lightbox gallery
- Floating pill navbar with mobile drawer, auto-hide on scroll
- Responsive down to 360px, keyboard accessible

## Pages

`index` · `about` · `doctors` · `gallery` · `blog` · `contact` · `appointment` · `registration` · `login` · `privacy` · `terms`

## Stack

- **HTML5** — semantic, one file per page
- **CSS** — a single stylesheet (`assets/css/modern.css`) using custom properties, grid, backdrop-filter, keyframes. No Tailwind, no preprocessor.
- **JavaScript** — a single file (`assets/js/modern.js`) with zero dependencies. Handles theme toggle, nav injection, reveals, counters, lightbox, and form demos.
- **Fonts** — Inter + Space Grotesk via Google Fonts

## Structure

```
.
├── index.html           # Home
├── about.html           # About / Vision / Mission / Values / Departments
├── doctors.html         # Team grid with hover socials
├── gallery.html         # Lightbox-enabled gallery
├── blog.html            # Featured + grid layout
├── contact.html         # Info cards + message form
├── appointment.html     # Booking form with time-slot picker
├── registration.html    # Auth split layout
├── login.html           # Auth split layout
├── privacy.html         # Prose page
├── terms.html           # Prose page
└── assets
    ├── css/modern.css
    ├── js/modern.js
    └── img/ (bg · blogs · gallery · slider · team)
```
