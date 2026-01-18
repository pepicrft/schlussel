import { listFormulas, formulas, Formula } from './formulas-data';
import { marked } from 'marked';

const css = `
:root {
  --yellow: #FFE135;
  --yellow-light: #FFF59D;
  --orange: #FF9F43;
  --coral: #FF6B6B;
  --purple: #A66CFF;
  --blue: #5D9CEC;
  --mint: #26DE81;
  --dark: #2D3436;
  --white: #FFFFFF;
  --cream: #FFFBF0;
  --shadow-cartoon: 4px 4px 0px var(--dark);
  --shadow-cartoon-lg: 8px 8px 0px var(--dark);
  --shadow-hover: 6px 6px 0px var(--dark);
  --border: 3px solid var(--dark);
  --border-thick: 4px solid var(--dark);
  --space-xs: 0.5rem;
  --space-sm: 1rem;
  --space-md: 2rem;
  --space-lg: 4rem;
  --space-xl: 6rem;
}

*, *::before, *::after { box-sizing: border-box; }

html {
  scroll-behavior: smooth;
}

body {
  margin: 0;
  padding: 0;
  font-family: 'Fredoka', sans-serif;
  font-size: 18px;
  line-height: 1.6;
  color: var(--dark);
  background: var(--cream);
  background-image:
    radial-gradient(circle at 20% 80%, rgba(166, 108, 255, 0.1) 0%, transparent 50%),
    radial-gradient(circle at 80% 20%, rgba(255, 225, 53, 0.2) 0%, transparent 50%),
    radial-gradient(circle at 50% 50%, rgba(93, 156, 236, 0.1) 0%, transparent 70%);
  min-height: 100vh;
}

h1, h2, h3, h4, h5, h6 {
  font-weight: 700;
  line-height: 1.2;
  margin: 0 0 var(--space-sm);
}

p { margin: 0 0 var(--space-sm); }

a {
  color: var(--purple);
  text-decoration: none;
  transition: all 0.2s ease;
}

a:hover { color: var(--coral); }

code {
  font-family: 'Space Mono', monospace;
  background: var(--yellow-light);
  padding: 0.2em 0.4em;
  border-radius: 4px;
  font-size: 0.9em;
  border: 2px solid var(--dark);
}

pre {
  font-family: 'Space Mono', monospace;
  background: var(--dark);
  color: var(--yellow);
  padding: var(--space-md);
  border-radius: 16px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  overflow-x: auto;
  font-size: 0.9rem;
  line-height: 1.5;
}

pre code {
  background: none;
  border: none;
  padding: 0;
  color: inherit;
}

.container {
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 var(--space-md);
}

.nav {
  padding: var(--space-sm) 0;
  position: sticky;
  top: 0;
  background: var(--cream);
  z-index: 100;
  border-bottom: var(--border);
}

.nav__inner {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.nav__brand {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--dark);
  text-decoration: none;
}

.nav__brand:hover {
  color: var(--dark);
  transform: rotate(-2deg);
}

.nav__key { font-size: 2rem; }

.nav__links {
  display: flex;
  gap: var(--space-md);
}

.nav__link {
  font-weight: 600;
  padding: var(--space-xs) var(--space-sm);
  border-radius: 8px;
  transition: all 0.2s ease;
}

.nav__link:hover {
  background: var(--yellow);
  color: var(--dark);
  transform: translateY(-2px);
}

.nav__toggle {
  display: none;
  flex-direction: column;
  gap: 5px;
  padding: var(--space-xs);
  background: none;
  border: none;
  cursor: pointer;
}

.nav__toggle span {
  display: block;
  width: 24px;
  height: 3px;
  background: var(--dark);
  border-radius: 2px;
  transition: all 0.3s ease;
}

.nav__toggle.active span:nth-child(1) {
  transform: rotate(45deg) translate(5px, 5px);
}

.nav__toggle.active span:nth-child(2) {
  opacity: 0;
}

.nav__toggle.active span:nth-child(3) {
  transform: rotate(-45deg) translate(6px, -6px);
}

.hero {
  padding: var(--space-xl) 0;
  text-align: center;
}

.hero__eyebrow {
  display: inline-block;
  background: var(--purple);
  color: var(--white);
  padding: var(--space-xs) var(--space-sm);
  border-radius: 50px;
  font-size: 0.9rem;
  font-weight: 600;
  border: var(--border);
  box-shadow: var(--shadow-cartoon);
  margin-bottom: var(--space-md);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.hero__title {
  font-size: clamp(2.5rem, 8vw, 5rem);
  margin-bottom: var(--space-md);
  line-height: 1.1;
}

.hero__title-highlight {
  display: inline-block;
  background: var(--yellow);
  padding: 0 0.2em;
  border-radius: 8px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
  transform: rotate(-1deg);
}

.hero__subtitle {
  font-size: 1.3rem;
  max-width: 650px;
  margin: 0 auto var(--space-lg);
  color: var(--dark);
  opacity: 0.9;
}

.hero__code {
  display: inline-block;
  background: var(--dark);
  color: var(--yellow);
  padding: var(--space-sm) var(--space-md);
  border-radius: 12px;
  font-family: 'Space Mono', monospace;
  font-size: 1.1rem;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  margin-bottom: var(--space-lg);
}

.hero__cta {
  display: flex;
  gap: var(--space-sm);
  justify-content: center;
  flex-wrap: wrap;
}

.btn {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-sm) var(--space-md);
  font-family: 'Fredoka', sans-serif;
  font-size: 1rem;
  font-weight: 600;
  border-radius: 12px;
  border: var(--border-thick);
  cursor: pointer;
  transition: all 0.2s ease;
  text-decoration: none;
}

.btn:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
}

.btn:active {
  transform: translate(0, 0);
  box-shadow: 2px 2px 0px var(--dark);
}

.btn--primary {
  background: var(--yellow);
  color: var(--dark);
  box-shadow: var(--shadow-cartoon);
}

.btn--secondary {
  background: var(--white);
  color: var(--dark);
  box-shadow: var(--shadow-cartoon);
}

.features {
  padding: var(--space-xl) 0;
}

.section__title {
  text-align: center;
  font-size: clamp(2rem, 5vw, 3rem);
  margin-bottom: var(--space-lg);
}

.features__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: var(--space-md);
}

.feature-card {
  background: var(--white);
  padding: var(--space-md);
  border-radius: 20px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  transition: all 0.3s ease;
}

.feature-card:hover {
  transform: translateY(-4px) rotate(1deg);
}

.feature-card:nth-child(2):hover {
  transform: translateY(-4px) rotate(-1deg);
}

.feature-card__icon {
  font-size: 3rem;
  margin-bottom: var(--space-sm);
}

.feature-card__title {
  font-size: 1.3rem;
  margin-bottom: var(--space-xs);
}

.feature-card__desc {
  opacity: 0.85;
  margin: 0;
}

.how-it-works {
  padding: var(--space-xl) 0;
  background: var(--yellow-light);
  border-top: var(--border-thick);
  border-bottom: var(--border-thick);
}

.steps {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
  max-width: 800px;
  margin: 0 auto;
}

.step {
  display: flex;
  gap: var(--space-md);
  align-items: flex-start;
  background: var(--white);
  padding: var(--space-md);
  border-radius: 16px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
}

.step__number {
  flex-shrink: 0;
  width: 50px;
  height: 50px;
  background: var(--purple);
  color: var(--white);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
  font-weight: 700;
  border: var(--border);
}

.step__content h3 { margin-bottom: var(--space-xs); }
.step__content p { margin: 0; opacity: 0.85; }

.formulas {
  padding: var(--space-xl) 0;
}

.formulas__intro {
  text-align: center;
  max-width: 700px;
  margin: 0 auto var(--space-lg);
  font-size: 1.1rem;
}

.formulas__list {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-sm);
  justify-content: center;
  margin-bottom: var(--space-lg);
}

.formula-badge {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  background: var(--white);
  padding: var(--space-xs) var(--space-sm);
  border-radius: 50px;
  border: var(--border);
  box-shadow: 3px 3px 0px var(--dark);
  font-weight: 500;
  transition: all 0.2s ease;
}

.formula-badge:hover {
  transform: translateY(-2px);
  box-shadow: var(--shadow-cartoon);
}

.formula-badge--github { background: var(--dark); color: var(--white); }
.formula-badge--linear { background: #5E6AD2; color: var(--white); }
.formula-badge--claude { background: #D97757; color: var(--white); }
.formula-badge--codex { background: #10A37F; color: var(--white); }

.search {
  max-width: 500px;
  margin: 0 auto var(--space-lg);
}

.search__input {
  width: 100%;
  padding: var(--space-sm) var(--space-md);
  font-family: 'Fredoka', sans-serif;
  font-size: 1.1rem;
  border: var(--border-thick);
  border-radius: 50px;
  box-shadow: var(--shadow-cartoon);
  outline: none;
  transition: all 0.2s ease;
}

.search__input:focus {
  box-shadow: var(--shadow-hover);
  transform: translateY(-2px);
}

.search__input::placeholder {
  color: var(--dark);
  opacity: 0.5;
}

.search__results {
  margin-top: var(--space-md);
  display: none;
}

.search__results.active {
  display: block;
}

.formula-card {
  background: var(--white);
  padding: var(--space-md);
  border-radius: 16px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
  margin-bottom: var(--space-sm);
  text-align: left;
}

.formula-card__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-xs);
  gap: var(--space-sm);
}

.formula-card__header > div {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.formula-card__title {
  font-size: 1.2rem;
  font-weight: 700;
  margin: 0;
}

.formula-card__id {
  font-family: 'Space Mono', monospace;
  font-size: 0.85rem;
  background: var(--yellow-light);
  padding: 0.2em 0.5em;
  border-radius: 4px;
  border: 2px solid var(--dark);
}

.formula-card__methods {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-xs);
  margin-top: var(--space-xs);
}

.formula-card__method {
  font-size: 0.8rem;
  background: var(--cream);
  padding: 0.2em 0.5em;
  border-radius: 4px;
  border: 2px solid var(--dark);
}

.formula-card__public-section {
  margin-top: var(--space-sm);
  padding-top: var(--space-sm);
  border-top: 2px dashed var(--dark);
}

.formula-card__public-label {
  font-size: 0.85rem;
  color: var(--dark);
  margin-bottom: var(--space-xs);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.formula-card__public-dot {
  width: 8px;
  height: 8px;
  background: var(--mint);
  border-radius: 50%;
  border: 2px solid var(--dark);
}

.formula-card__command {
  font-family: 'Space Mono', monospace;
  font-size: 0.85rem;
  background: var(--dark);
  color: var(--yellow);
  padding: 0.5em 0.75em;
  border-radius: 8px;
  border: 2px solid var(--dark);
  display: block;
  overflow-x: auto;
}

.cta {
  padding: var(--space-xl) 0;
  text-align: center;
}

.cta__box {
  background: var(--purple);
  color: var(--white);
  padding: var(--space-lg);
  border-radius: 24px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  position: relative;
  overflow: hidden;
}

.cta__box::before {
  content: '';
  position: absolute;
  top: -50%;
  right: -50%;
  width: 100%;
  height: 100%;
  background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
}

.cta__title {
  font-size: clamp(1.8rem, 4vw, 2.5rem);
  margin-bottom: var(--space-sm);
  position: relative;
}

.cta__desc {
  font-size: 1.1rem;
  margin-bottom: var(--space-md);
  opacity: 0.95;
  position: relative;
}

.cta .btn--primary {
  background: var(--yellow);
  position: relative;
}

.footer {
  padding: var(--space-md) 0;
  text-align: center;
  border-top: var(--border);
  font-size: 0.9rem;
  opacity: 0.8;
}

.footer a {
  color: var(--dark);
  font-weight: 600;
}

.reflection {
  padding: var(--space-xl) 0;
  background: var(--white);
  border-top: var(--border-thick);
  border-bottom: var(--border-thick);
}

.reflection__content {
  max-width: 800px;
  margin: 0 auto;
}

.reflection__title {
  font-size: clamp(1.8rem, 4vw, 2.5rem);
  margin-bottom: var(--space-md);
  text-align: center;
}

.reflection__text {
  font-size: 1.1rem;
  line-height: 1.8;
  margin-bottom: var(--space-md);
}

.reflection__text:last-of-type {
  margin-bottom: 0;
}

.reflection__highlight {
  background: var(--yellow-light);
  padding: 0.1em 0.3em;
  border-radius: 4px;
  border: 2px solid var(--dark);
}

.reflection__quote {
  background: var(--cream);
  padding: var(--space-md);
  border-radius: 16px;
  border: var(--border);
  margin: var(--space-md) 0;
  font-style: italic;
}

.reflection__quote-source {
  display: block;
  margin-top: var(--space-sm);
  font-style: normal;
  font-weight: 600;
  font-size: 0.9rem;
}

@media (max-width: 900px) {
  .nav__toggle {
    display: flex;
  }

  .nav__links {
    display: none;
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: var(--cream);
    border-bottom: var(--border);
    padding: var(--space-sm);
    flex-direction: column;
    gap: var(--space-xs);
  }

  .nav__links.open {
    display: flex;
  }

  .nav__link {
    padding: var(--space-sm);
    text-align: center;
  }

  .nav__inner {
    position: relative;
  }
}

@media (max-width: 768px) {
  :root {
    --space-lg: 3rem;
    --space-xl: 4rem;
  }

  .hero__code {
    font-size: 0.85rem;
    padding: var(--space-xs) var(--space-sm);
  }

  .step {
    flex-direction: column;
    text-align: center;
  }

  .step__number { margin: 0 auto; }

  .hero__cta {
    flex-direction: column;
    align-items: center;
  }

  .playground__auth {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-xs);
  }

  .playground__auth-status {
    margin-left: 0;
  }

  .playground__device-code-value {
    font-size: 1.5rem;
  }

  .playground__editor-hint {
    font-size: 0.65rem;
  }
}
`;

function getFormulaBadgeClass(id: string): string {
  switch (id) {
    case 'github': return 'formula-badge--github';
    case 'linear': return 'formula-badge--linear';
    case 'claude': return 'formula-badge--claude';
    case 'codex': return 'formula-badge--codex';
    default: return '';
  }
}

export function renderHomepage(): string {
  const formulaList = listFormulas();
  const formulaBadges = formulaList.map(f => {
    const colorClass = getFormulaBadgeClass(f.id);
    return '<a href="/formulas/' + f.id + '" class="formula-badge ' + colorClass + '">' + f.label + '</a>';
  }).join('\n        ');

  const title = 'Schlussel - Auth Runtime for Agents';
  const description = 'The local authentication runtime for agents. Codify how users authenticate, guide them through OAuth flows, and keep sessions safe with native storage and locked refreshes. curl + schlussel is all you need.';
  const url = 'https://schlussel.me';

  return '<!DOCTYPE html>\n' +
'<html lang="en">\n' +
'<head>\n' +
'  <meta charset="UTF-8">\n' +
'  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
'  <title>' + title + '</title>\n' +
'  <meta name="description" content="' + description + '">\n' +
'  <meta name="keywords" content="authentication, oauth, agents, cli, runtime, tokens, api, github, linear, claude, codex">\n' +
'  <meta name="author" content="Pedro Pinera">\n' +
'  <link rel="canonical" href="' + url + '">\n' +
'  <link rel="icon" type="image/png" href="/favicon.png">\n' +
'  <!-- Open Graph / Facebook -->\n' +
'  <meta property="og:type" content="website">\n' +
'  <meta property="og:url" content="' + url + '">\n' +
'  <meta property="og:title" content="' + title + '">\n' +
'  <meta property="og:description" content="' + description + '">\n' +
'  <meta property="og:site_name" content="Schlussel">\n' +
'  <meta property="og:image" content="' + url + '/og.png">\n' +
'  <meta property="og:image:width" content="1200">\n' +
'  <meta property="og:image:height" content="630">\n' +
'  <!-- Twitter -->\n' +
'  <meta name="twitter:card" content="summary_large_image">\n' +
'  <meta name="twitter:url" content="' + url + '">\n' +
'  <meta name="twitter:title" content="' + title + '">\n' +
'  <meta name="twitter:description" content="' + description + '">\n' +
'  <meta name="twitter:image" content="' + url + '/og.png">\n' +
'  <meta name="twitter:site" content="@pepicrft">\n' +
'  <meta name="twitter:creator" content="@pepicrft">\n' +
'  <!-- Additional SEO -->\n' +
'  <meta name="robots" content="index, follow">\n' +
'  <meta name="googlebot" content="index, follow">\n' +
'  <link rel="preconnect" href="https://fonts.googleapis.com">\n' +
'  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n' +
'  <link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">\n' +
'  <style>' + css + '</style>\n' +
'</head>\n' +
'<body>\n' +
'  <nav class="nav">\n' +
'    <div class="container nav__inner">\n' +
'      <a href="/" class="nav__brand">\n' +
'        <span class="nav__key">🔑</span>\n' +
'        <span>schlussel</span>\n' +
'      </a>\n' +
'      <button class="nav__toggle" aria-label="Toggle menu">\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'      </button>\n' +
'      <div class="nav__links">\n' +
'        <a href="#features" class="nav__link">Features</a>\n' +
'        <a href="#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/docs" class="nav__link">Docs</a>\n' +
'        <a href="/skill" class="nav__link">SKILL.md</a>\n' +
'        <a href="https://github.com/pepicrft/schlussel" class="nav__link">GitHub</a>\n' +
'      </div>\n' +
'    </div>\n' +
'  </nav>\n' +
'\n' +
'  <main>\n' +
'    <section class="hero">\n' +
'      <div class="container">\n' +
'        <span class="hero__eyebrow">Auth Runtime for Agents</span>\n' +
'        <h1 class="hero__title">\n' +
'          <span class="hero__title-highlight">curl + schlussel</span><br>\n' +
'          is all you need\n' +
'        </h1>\n' +
'        <p class="hero__subtitle">\n' +
'          The local authentication runtime for agents. Codify how users authenticate,\n' +
'          guide them through the right steps, and keep sessions safe with native\n' +
'          storage and locked refreshes.\n' +
'        </p>\n' +
'        <div class="hero__code">\n' +
'          $ mise use -g github:pepicrft/schlussel\n' +
'        </div>\n' +
'        <div class="hero__cta">\n' +
'          <a href="https://github.com/pepicrft/schlussel" class="btn btn--primary">\n' +
'            Get Started\n' +
'          </a>\n' +
'          <a href="#how-it-works" class="btn btn--secondary">\n' +
'            Learn More\n' +
'          </a>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="features" id="features">\n' +
'      <div class="container">\n' +
'        <h2 class="section__title">Why Schlussel?</h2>\n' +
'        <div class="features__grid">\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">⚡</div>\n' +
'            <h3 class="feature-card__title">Fast</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              Agents query a formula and get everything: auth flow, API endpoints,\n' +
'              headers, specs. No searching the web. Just authenticate and call.\n' +
'            </p>\n' +
'          </div>\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">🔄</div>\n' +
'            <h3 class="feature-card__title">No More Race Conditions</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              Cross-process locking prevents multiple agents from refreshing\n' +
'              the same token simultaneously. One refresh, shared result.\n' +
'            </p>\n' +
'          </div>\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">📋</div>\n' +
'            <h3 class="feature-card__title">Formula-Driven</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              All platform knowledge lives in portable JSON recipes. OAuth flows,\n' +
'              API keys, PATs. Add new platforms without code changes.\n' +
'            </p>\n' +
'          </div>\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">🖥️</div>\n' +
'            <h3 class="feature-card__title">CLI-Native</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              Agents shell out to Schlussel. No SDKs, no daemons, no servers.\n' +
'              Just a binary that does one thing well.\n' +
'            </p>\n' +
'          </div>\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">🌍</div>\n' +
'            <h3 class="feature-card__title">Cross-Platform</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              Works on macOS, Linux, and Windows. x86_64 and ARM64.\n' +
'              Built in Zig for zero dependencies.\n' +
'            </p>\n' +
'          </div>\n' +
'          <div class="feature-card">\n' +
'            <div class="feature-card__icon">🏠</div>\n' +
'            <h3 class="feature-card__title">Local-First</h3>\n' +
'            <p class="feature-card__desc">\n' +
'              Credentials never leave your machine. Schlussel is not a cloud\n' +
'              service. Your auth, your control.\n' +
'            </p>\n' +
'          </div>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="how-it-works" id="how-it-works">\n' +
'      <div class="container">\n' +
'        <h2 class="section__title">How It Works</h2>\n' +
'        <div class="steps">\n' +
'          <div class="step">\n' +
'            <div class="step__number">1</div>\n' +
'            <div class="step__content">\n' +
'              <h3>Agent Needs Auth</h3>\n' +
'              <p>\n' +
'                Your agent (Claude, Codex, custom script) needs to call GitHub, Linear, or any API.\n' +
'                Instead of managing tokens itself, it asks Schlussel.\n' +
'              </p>\n' +
'            </div>\n' +
'          </div>\n' +
'          <div class="step">\n' +
'            <div class="step__number">2</div>\n' +
'            <div class="step__content">\n' +
'              <h3>Schlussel Handles the Flow</h3>\n' +
'              <p>\n' +
'                Schlussel auto-selects a public client and method when available, checks for existing tokens,\n' +
'                refreshes if needed (with locking), or guides the user through OAuth. All based on the formula for that platform.\n' +
'              </p>\n' +
'            </div>\n' +
'          </div>\n' +
'          <div class="step">\n' +
'            <div class="step__number">3</div>\n' +
'            <div class="step__content">\n' +
'              <h3>Agent Gets a Token</h3>\n' +
'              <p>\n' +
'                The agent receives a valid access token. It can now make API calls.\n' +
'                Schlussel handles the complexity, the agent stays simple.\n' +
'              </p>\n' +
'            </div>\n' +
'          </div>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="reflection" id="why">\n' +
'      <div class="container">\n' +
'        <div class="reflection__content">\n' +
'          <h2 class="reflection__title">The Auth Narrow Waist for Agents</h2>\n' +
'          <p class="reflection__text">\n' +
'            Not every service on the internet exposes an API. Many are hesitant, watching how\n' +
'            a new layer of agentic applications and LLMs might extract value from their platforms\n' +
'            the same way tech giants once built empires on top of telecommunications infrastructure.\n' +
'            The fear is real: become the "dumb pipe" while others capture the margin.\n' +
'          </p>\n' +
'          <p class="reflection__text">\n' +
'            Others do expose APIs, but they are not productized beyond their own SPAs.\n' +
'            Browser-generated cookies, CORS restrictions, sessions tied to web flows.\n' +
'            The API exists, but it was never meant for you. It was meant for their frontend.\n' +
'          </p>\n' +
'          <div class="reflection__quote">\n' +
'            "The Internet is the first thing that humanity has built that humanity does not understand,\n' +
'            the largest experiment in anarchy that we have ever had."\n' +
'            <span class="reflection__quote-source">- Eric Schmidt</span>\n' +
'          </div>\n' +
'          <p class="reflection__text">\n' +
'            But this tension is not new. TCP/IP became the <span class="reflection__highlight">narrow waist</span>\n' +
'            of networking, a simple contract that enabled everything above and below it to evolve independently.\n' +
'            The shipping container standardized global trade. HTTP standardized the web.\n' +
'            Each time, the "dumb" layer unlocked exponential value for everyone.\n' +
'          </p>\n' +
'          <p class="reflection__text">\n' +
'            Agents talking to APIs is inevitable. The question is not if, but how.\n' +
'            Schlussel is our bet on what that narrow waist looks like: a simple contract\n' +
'            where authentication flows are codified in portable formulas, sessions are managed\n' +
'            locally, and every agent speaks the same language to every API.\n' +
'          </p>\n' +
'          <p class="reflection__text">\n' +
'            We are not building a platform. We are building <span class="reflection__highlight">the shipping container</span>\n' +
'            between agents and the services they need to access.\n' +
'          </p>\n' +
'          <p class="reflection__text">\n' +
'            If you are building a service, consider adopting <a href="https://datatracker.ietf.org/doc/html/rfc7591">OAuth 2.0 Dynamic Client Registration (RFC 7591)</a>\n' +
'            and <a href="https://datatracker.ietf.org/doc/html/rfc8628">Device Authorization Grant (RFC 8628)</a>.\n' +
'            These are the most agent-friendly standards: no browser redirects, no pre-registered clients,\n' +
'            just a code on a screen and a polling loop. Perfect for headless environments where LLMs operate.\n' +
'          </p>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="formulas" id="formulas">\n' +
'      <div class="container">\n' +
'        <h2 class="section__title">Built-in Formulas</h2>\n' +
'        <p class="formulas__intro">\n' +
'          Schlussel ships with curated formulas for popular platforms. Each formula knows\n' +
'          the OAuth endpoints, scopes, and even includes public client credentials\n' +
'          when available. Formulas are actively maintained and verified for accuracy.\n' +
'          When a formula has a public client, Schlussel auto-selects it. Just run and authenticate.\n' +
'        </p>\n' +
'        <div class="search">\n' +
'          <input type="text" class="search__input" id="formula-search" placeholder="Search formulas (e.g. github, oauth, api_key...)">\n' +
'          <div class="search__results" id="search-results"></div>\n' +
'        </div>\n' +
'        <div class="formulas__list" id="formula-badges">\n' +
'          ' + formulaBadges + '\n' +
'          <span class="formula-badge">+ Your Own</span>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="cta">\n' +
'      <div class="container">\n' +
'        <div class="cta__box">\n' +
'          <h2 class="cta__title">Ready to simplify auth?</h2>\n' +
'          <p class="cta__desc">\n' +
'            One binary. Many platforms. Zero split-brain sessions.\n' +
'          </p>\n' +
'          <a href="https://github.com/pepicrft/schlussel" class="btn btn--primary">\n' +
'            View on GitHub\n' +
'          </a>\n' +
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'  </main>\n' +
'\n' +
'  <footer class="footer">\n' +
'    <div class="container">\n' +
'      <p>\n' +
'        Made with love by <a href="https://pepicrft.me">Pedro Pinera</a>.\n' +
'        Licensed under MIT.\n' +
'      </p>\n' +
'    </div>\n' +
'  </footer>\n' +
'  <script>\n' +
'    const formulasData = ' + JSON.stringify(formulas) + ';\n' +
'    const searchInput = document.getElementById("formula-search");\n' +
'    const searchResults = document.getElementById("search-results");\n' +
'    const formulaBadgesEl = document.getElementById("formula-badges");\n' +
'\n' +
'    function searchFormulas(query) {\n' +
'      const q = query.toLowerCase();\n' +
'      return Object.values(formulasData).filter(f =>\n' +
'        f.id.toLowerCase().includes(q) ||\n' +
'        f.label.toLowerCase().includes(q) ||\n' +
'        Object.keys(f.methods).some(m => m.toLowerCase().includes(q))\n' +
'      );\n' +
'    }\n' +
'\n' +
'    function renderResults(results) {\n' +
'      if (results.length === 0) {\n' +
'        return "<p style=\\"text-align:center;opacity:0.7\\">No formulas found</p>";\n' +
'      }\n' +
'      return results.map(f => {\n' +
'        const methods = Object.keys(f.methods).map(m =>\n' +
'          "<span class=\\"formula-card__method\\">" + m + "</span>"\n' +
'        ).join("");\n' +
'        const hasPublicClient = f.clients && f.clients.length > 0;\n' +
'        const publicSection = hasPublicClient ?\n' +
'          "<div class=\\"formula-card__public-section\\">" +\n' +
'            "<div class=\\"formula-card__public-label\\">" +\n' +
'              "<span class=\\"formula-card__public-dot\\"></span>" +\n' +
'              "Contains a public client" +\n' +
'            "</div>" +\n' +
'            "<code class=\\"formula-card__command\\">$ schlussel run " + f.id + "</code>" +\n' +
'          "</div>" : "";\n' +
'        return "<a href=\\"/formulas/" + f.id + "\\" class=\\"formula-card\\" style=\\"display:block;text-decoration:none;color:inherit;\\">" +\n' +
'          "<div class=\\"formula-card__header\\">" +\n' +
'            "<h4 class=\\"formula-card__title\\">" + f.label + "</h4>" +\n' +
'            "<span class=\\"formula-card__id\\">" + f.id + "</span>" +\n' +
'          "</div>" +\n' +
'          "<div class=\\"formula-card__methods\\">" + methods + "</div>" +\n' +
'          publicSection +\n' +
'        "</a>";\n' +
'      }).join("");\n' +
'    }\n' +
'\n' +
'    searchInput.addEventListener("input", (e) => {\n' +
'      const query = e.target.value.trim();\n' +
'      if (query.length === 0) {\n' +
'        searchResults.classList.remove("active");\n' +
'        formulaBadgesEl.style.display = "flex";\n' +
'        return;\n' +
'      }\n' +
'      const results = searchFormulas(query);\n' +
'      searchResults.innerHTML = renderResults(results);\n' +
'      searchResults.classList.add("active");\n' +
'      formulaBadgesEl.style.display = "none";\n' +
'    });\n' +
'\n' +
'    // Mobile nav toggle\n' +
'    const navToggle = document.querySelector(".nav__toggle");\n' +
'    const navLinks = document.querySelector(".nav__links");\n' +
'    navToggle.addEventListener("click", () => {\n' +
'      navToggle.classList.toggle("active");\n' +
'      navLinks.classList.toggle("open");\n' +
'    });\n' +
'  </script>\n' +
'</body>\n' +
'</html>';
}

const formulaPageCss = `
.formula-page {
  padding: var(--space-lg) 0;
}

.formula-header {
  margin-bottom: var(--space-lg);
}

.formula-header__breadcrumb {
  font-size: 0.9rem;
  margin-bottom: var(--space-sm);
}

.formula-header__breadcrumb a {
  color: var(--purple);
}

.formula-header__title {
  font-size: clamp(2rem, 5vw, 3rem);
  margin-bottom: var(--space-xs);
}

.formula-header__id {
  font-family: 'Space Mono', monospace;
  font-size: 1rem;
  background: var(--yellow-light);
  padding: 0.3em 0.6em;
  border-radius: 6px;
  border: 2px solid var(--dark);
  display: inline-block;
  margin-bottom: var(--space-sm);
}

.formula-header__desc {
  font-size: 1.1rem;
  max-width: 700px;
  opacity: 0.9;
}

.formula-section {
  background: var(--white);
  padding: var(--space-md);
  border-radius: 20px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
  margin-bottom: var(--space-md);
}

.formula-section__title {
  font-size: 1.3rem;
  margin-bottom: var(--space-sm);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.formula-section__icon {
  font-size: 1.5rem;
}

.formula-method {
  background: var(--cream);
  padding: var(--space-sm);
  border-radius: 12px;
  border: var(--border);
  margin-bottom: var(--space-sm);
}

.formula-method:last-child {
  margin-bottom: 0;
}

.formula-method__name {
  font-weight: 700;
  font-size: 1.1rem;
  margin-bottom: var(--space-xs);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.formula-method__label {
  font-size: 0.8rem;
  background: var(--purple);
  color: var(--white);
  padding: 0.2em 0.5em;
  border-radius: 4px;
  font-weight: 500;
}

.formula-method__detail {
  font-size: 0.9rem;
  margin-bottom: var(--space-xs);
}

.formula-method__detail-label {
  font-weight: 600;
  color: var(--dark);
}

.formula-method__detail-value {
  font-family: 'Space Mono', monospace;
  font-size: 0.85rem;
  background: var(--yellow-light);
  padding: 0.1em 0.3em;
  border-radius: 4px;
  word-break: break-all;
}

.formula-api {
  background: var(--cream);
  padding: var(--space-sm);
  border-radius: 12px;
  border: var(--border);
  margin-bottom: var(--space-sm);
}

.formula-api:last-child {
  margin-bottom: 0;
}

.formula-api__name {
  font-weight: 700;
  font-size: 1.1rem;
  margin-bottom: var(--space-xs);
}

.formula-api__detail {
  font-size: 0.9rem;
  margin-bottom: var(--space-xs);
}

.formula-api__detail:last-child {
  margin-bottom: 0;
}

.formula-client {
  background: var(--cream);
  padding: var(--space-sm);
  border-radius: 12px;
  border: var(--border);
  margin-bottom: var(--space-sm);
}

.formula-client:last-child {
  margin-bottom: 0;
}

.formula-client__name {
  font-weight: 700;
  font-size: 1.1rem;
  margin-bottom: var(--space-xs);
}

.formula-client__detail {
  font-size: 0.9rem;
  margin-bottom: var(--space-xs);
}

.formula-client__command {
  font-family: 'Space Mono', monospace;
  font-size: 0.9rem;
  background: var(--dark);
  color: var(--yellow);
  padding: var(--space-sm);
  border-radius: 8px;
  border: 2px solid var(--dark);
  display: block;
  margin-top: var(--space-xs);
}

.formula-steps {
  list-style: none;
  padding: 0;
  margin: 0;
}

.formula-steps li {
  padding: var(--space-xs) 0;
  padding-left: var(--space-md);
  position: relative;
}

.formula-steps li::before {
  content: '→';
  position: absolute;
  left: 0;
  color: var(--purple);
  font-weight: 700;
}

.formula-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: var(--space-md);
}

.formula-back {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  margin-top: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  background: var(--yellow);
  border-radius: 12px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
  font-weight: 600;
  transition: all 0.2s ease;
}

.formula-back:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
  color: var(--dark);
}

/* Playground styles */
.playground {
  margin-top: var(--space-lg);
}

.playground__title {
  font-size: 1.5rem;
  margin-bottom: var(--space-sm);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.playground__desc {
  margin-bottom: var(--space-md);
  opacity: 0.85;
}

.playground__auth {
  margin-bottom: var(--space-md);
}

.playground__auth-btn {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-sm) var(--space-md);
  background: var(--mint);
  border: var(--border-thick);
  border-radius: 12px;
  box-shadow: var(--shadow-cartoon);
  font-family: 'Fredoka', sans-serif;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
}

.playground__auth-btn:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
}

.playground__auth-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  transform: none;
  box-shadow: var(--shadow-cartoon);
}

.playground__auth-status {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  margin-left: var(--space-sm);
  font-size: 0.9rem;
}

.playground__auth-status--success {
  color: var(--mint);
}

.playground__auth-status--error {
  color: var(--coral);
}

.playground__auth-status--info {
  color: var(--blue);
}

.playground__device-code {
  background: var(--white);
  padding: var(--space-md);
  border-radius: 16px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon);
  margin-bottom: var(--space-md);
  text-align: center;
}

.playground__device-code p {
  margin-bottom: var(--space-sm);
}

.playground__device-code a {
  color: var(--purple);
  font-weight: 600;
}

.playground__device-code-value {
  font-family: 'Space Mono', monospace;
  font-size: 2rem;
  font-weight: 700;
  background: var(--yellow-light);
  padding: var(--space-sm) var(--space-md);
  border-radius: 12px;
  border: var(--border-thick);
  display: inline-block;
  margin-bottom: var(--space-sm);
  letter-spacing: 0.1em;
}

.playground__device-code-copy {
  display: inline-block;
  padding: var(--space-xs) var(--space-sm);
  background: var(--purple);
  color: var(--white);
  border: var(--border);
  border-radius: 8px;
  font-family: 'Fredoka', sans-serif;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
}

.playground__device-code-copy:hover {
  transform: scale(1.05);
}

.playground__console {
  background: var(--white);
  border-radius: 16px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  overflow: hidden;
}

.playground__console-header {
  background: var(--dark);
  color: var(--white);
  padding: var(--space-xs) var(--space-sm);
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: var(--border-thick);
}

.playground__console-dots {
  display: flex;
  gap: 6px;
}

.playground__console-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  border: 2px solid var(--dark);
}

.playground__console-dot--red { background: var(--coral); }
.playground__console-dot--yellow { background: var(--yellow); }
.playground__console-dot--green { background: var(--mint); }

.playground__console-title {
  font-family: 'Space Mono', monospace;
  font-size: 0.85rem;
}

.playground__editor {
  position: relative;
  background: #1a1a2e;
  border-bottom: 2px solid #333;
}

.playground__editor-hint {
  position: absolute;
  bottom: 8px;
  right: 16px;
  font-size: 0.75rem;
  color: #666;
  font-family: 'Space Mono', monospace;
  pointer-events: none;
  z-index: 10;
}

.playground__run-btn {
  display: flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-xs) var(--space-sm);
  background: var(--yellow);
  border: var(--border);
  border-radius: 8px;
  font-family: 'Fredoka', sans-serif;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
}

.playground__run-btn:hover {
  transform: scale(1.05);
}

.playground__run-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  transform: none;
}

.playground__output {
  background: var(--dark);
  color: var(--yellow);
  min-height: 100px;
  max-height: 300px;
  overflow-y: auto;
  padding: var(--space-sm);
  font-family: 'Space Mono', monospace;
  font-size: 0.85rem;
  line-height: 1.5;
}

.playground__output-line {
  margin-bottom: 4px;
  white-space: pre-wrap;
  word-break: break-all;
}

.playground__output-line--error {
  color: var(--coral);
}

.playground__output-line--info {
  color: var(--blue);
}

.playground__output-empty {
  opacity: 0.5;
  font-style: italic;
}

.playground__headers-preview {
  background: #252540;
  padding: var(--space-sm);
  border-bottom: 2px solid #333;
  font-family: 'Space Mono', monospace;
  font-size: 0.8rem;
  color: #a0a0a0;
}

.playground__headers-label {
  font-weight: 600;
  margin-bottom: 4px;
  font-family: 'Fredoka', sans-serif;
  color: #888;
}

.playground__headers-value {
  color: #26DE81;
}
`;

export function renderFormulaPage(formula: Formula): string {
  const title = formula.label + ' Authentication - Schlussel';
  const description = formula.description || 'Authenticate with ' + formula.label + ' using Schlussel, the auth runtime for agents.';
  const url = 'https://schlussel.me/formulas/' + formula.id;

  // Render methods section
  const methodsHtml = Object.entries(formula.methods).map(([methodId, method]) => {
    let details = '';

    if (method.label) {
      details += '<div class="formula-method__detail"><span class="formula-method__label">' + method.label + '</span></div>';
    }

    if (method.endpoints) {
      const endpointsHtml = Object.entries(method.endpoints).map(([key, value]) =>
        '<div class="formula-method__detail"><span class="formula-method__detail-label">' + key + ':</span> <span class="formula-method__detail-value">' + value + '</span></div>'
      ).join('');
      details += endpointsHtml;
    }

    if (method.scope) {
      details += '<div class="formula-method__detail"><span class="formula-method__detail-label">Scope:</span> <span class="formula-method__detail-value">' + method.scope + '</span></div>';
    }

    if (method.register) {
      details += '<div class="formula-method__detail"><span class="formula-method__detail-label">Register at:</span> <a href="' + method.register.url + '" target="_blank">' + method.register.url + '</a></div>';
      if (method.register.steps && method.register.steps.length > 0) {
        details += '<ul class="formula-steps">' + method.register.steps.map(step => '<li>' + step + '</li>').join('') + '</ul>';
      }
    }

    return '<div class="formula-method">' +
      '<div class="formula-method__name">' + methodId + '</div>' +
      details +
    '</div>';
  }).join('');

  // Render APIs section
  let apisHtml = '';
  if (formula.apis) {
    const apisContent = Object.entries(formula.apis).map(([apiId, api]) => {
      let apiDetails = '';
      apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Base URL:</span> <span class="formula-method__detail-value">' + api.base_url + '</span></div>';
      apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Auth Header:</span> <span class="formula-method__detail-value">' + api.auth_header + '</span></div>';
      if (api.docs_url) {
        apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Docs:</span> <a href="' + api.docs_url + '" target="_blank">' + api.docs_url + '</a></div>';
      }
      if (api.spec_type) {
        apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Spec Type:</span> <span class="formula-method__detail-value">' + api.spec_type + '</span></div>';
      }
      if (api.methods && api.methods.length > 0) {
        apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Methods:</span> ' + api.methods.map(m => '<span class="formula-method__detail-value">' + m + '</span>').join(' ') + '</div>';
      }
      if (api.variables) {
        const varsHtml = Object.entries(api.variables).map(([varName, varDef]) => {
          let varInfo = '<code>{' + varName + '}</code>';
          if (varDef.hint) varInfo += ' - ' + varDef.hint;
          if (varDef.example) varInfo += ' (e.g., <code>' + varDef.example + '</code>)';
          return varInfo;
        }).join(', ');
        apiDetails += '<div class="formula-api__detail"><span class="formula-method__detail-label">Variables:</span> ' + varsHtml + '</div>';
      }
      return '<div class="formula-api"><div class="formula-api__name">' + apiId + '</div>' + apiDetails + '</div>';
    }).join('');
    apisHtml = '<div class="formula-section">' +
      '<h3 class="formula-section__title"><span class="formula-section__icon">🌐</span> APIs</h3>' +
      apisContent +
    '</div>';
  }

  // Render clients section
  let clientsHtml = '';
  if (formula.clients && formula.clients.length > 0) {
    const clientsContent = formula.clients.map(client => {
      let clientDetails = '';
      clientDetails += '<div class="formula-client__detail"><span class="formula-method__detail-label">Client ID:</span> <span class="formula-method__detail-value">' + client.id + '</span></div>';
      if (client.source) {
        clientDetails += '<div class="formula-client__detail"><span class="formula-method__detail-label">Source:</span> <a href="' + client.source + '" target="_blank">' + client.source + '</a></div>';
      }
      if (client.methods && client.methods.length > 0) {
        clientDetails += '<div class="formula-client__detail"><span class="formula-method__detail-label">Methods:</span> ' + client.methods.map(m => '<span class="formula-method__detail-value">' + m + '</span>').join(' ') + '</div>';
      }
      clientDetails += '<code class="formula-client__command">$ schlussel run ' + formula.id + '</code>';
      return '<div class="formula-client"><div class="formula-client__name">' + client.name + '</div>' + clientDetails + '</div>';
    }).join('');
    clientsHtml = '<div class="formula-section">' +
      '<h3 class="formula-section__title"><span class="formula-section__icon">📦</span> Public Clients</h3>' +
      '<p style="margin-bottom: var(--space-sm); opacity: 0.85;">These clients are bundled with the formula. Schlussel auto-selects the first available public client and its supported method. Just run the command below.</p>' +
      clientsContent +
    '</div>';
  }

  // Identity hint section
  let identityHtml = '';
  if (formula.identity) {
    identityHtml = '<div class="formula-section">' +
      '<h3 class="formula-section__title"><span class="formula-section__icon">👤</span> Identity</h3>' +
      '<div class="formula-method__detail"><span class="formula-method__detail-label">' + (formula.identity.label || 'Account') + ':</span> ' + (formula.identity.hint || 'Specify an identifier for this account') + '</div>' +
    '</div>';
  }

  // Playground section - only for formulas with public clients that support device_code
  let playgroundHtml = '';
  let playgroundScript = '';
  const playgroundClient = formula.clients?.find(c => c.methods?.includes('device_code'));
  const deviceCodeMethod = formula.methods?.device_code;
  const restApi = formula.apis?.rest;

  if (playgroundClient && deviceCodeMethod && restApi) {
    const deviceUrl = deviceCodeMethod.endpoints?.device || '';
    const tokenUrl = deviceCodeMethod.endpoints?.token || '';
    const scope = deviceCodeMethod.scope || '';
    const clientId = playgroundClient.id;
    const clientSecret = playgroundClient.secret || '';
    const baseUrl = restApi.base_url;
    const exampleEndpoint = restApi.example_endpoint || '/';
    const exampleUrl = baseUrl + exampleEndpoint;

    playgroundHtml = `
      <div class="playground" id="playground">
        <h2 class="playground__title">🎮 API Playground</h2>
        <p class="playground__desc">
          Authenticate with ${formula.label} and try the API right here. Your token stays in your browser and is not stored.
        </p>

        <div class="playground__auth">
          <button class="playground__auth-btn" id="auth-btn">
            🔐 Authenticate with ${formula.label}
          </button>
          <span class="playground__auth-status" id="auth-status"></span>
        </div>

        <div class="playground__device-code" id="device-code-box" style="display: none;">
          <p>Open <a id="device-link" href="#" target="_blank"></a> and enter this code:</p>
          <div class="playground__device-code-value" id="device-code-value"></div>
          <div>
            <button class="playground__device-code-copy" id="copy-code-btn">Copy Code</button>
          </div>
        </div>

        <div class="playground__console">
          <div class="playground__console-header">
            <div class="playground__console-dots">
              <span class="playground__console-dot playground__console-dot--red"></span>
              <span class="playground__console-dot playground__console-dot--yellow"></span>
              <span class="playground__console-dot playground__console-dot--green"></span>
            </div>
            <span class="playground__console-title">console</span>
            <button class="playground__run-btn" id="run-btn" disabled>▶ Run</button>
          </div>
          <div class="playground__headers-preview" id="headers-preview" style="display: none;">
            <div class="playground__headers-label">Available after auth:</div>
            <div class="playground__headers-value">const headers = { "Authorization": "Bearer ..." }</div>
          </div>
          <div class="playground__editor">
            <div id="code-editor" style="height: 180px;"></div>
            <span class="playground__editor-hint">Cmd/Ctrl + Enter to run</span>
          </div>
          <div class="playground__output" id="output">
            <div class="playground__output-empty">Output will appear here...</div>
          </div>
        </div>
      </div>
    `;

    playgroundScript = `
  <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs/loader.js"></script>
  <script>
    (function() {
      const authBtn = document.getElementById('auth-btn');
      const authStatus = document.getElementById('auth-status');
      const runBtn = document.getElementById('run-btn');
      const editorContainer = document.getElementById('code-editor');
      const output = document.getElementById('output');
      const headersPreview = document.getElementById('headers-preview');
      const deviceCodeBox = document.getElementById('device-code-box');
      const deviceCodeValue = document.getElementById('device-code-value');
      const deviceLink = document.getElementById('device-link');
      const copyCodeBtn = document.getElementById('copy-code-btn');

      let token = null;
      let headers = null;
      let editor = null;

      // Default code
      const defaultCode = \`// After auth, 'headers' will contain your Authorization header

const res = await fetch('${exampleUrl}', { headers })
const data = await res.json()
console.log(data)\`;

      // Initialize Monaco Editor
      require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs' } });
      require(['vs/editor/editor.main'], function () {
        // Define a dark theme matching our console
        monaco.editor.defineTheme('playground-dark', {
          base: 'vs-dark',
          inherit: true,
          rules: [],
          colors: {
            'editor.background': '#1a1a2e',
            'editor.lineHighlightBackground': '#252540',
            'editorLineNumber.foreground': '#666',
            'editorCursor.foreground': '#FFE135'
          }
        });

        editor = monaco.editor.create(editorContainer, {
          value: defaultCode,
          language: 'javascript',
          theme: 'playground-dark',
          minimap: { enabled: false },
          fontSize: 14,
          lineNumbers: 'on',
          scrollBeyondLastLine: false,
          automaticLayout: true,
          tabSize: 2,
          wordWrap: 'on',
          padding: { top: 12, bottom: 12 }
        });

        // Add Cmd/Ctrl+Enter to run
        editor.addAction({
          id: 'run-code',
          label: 'Run Code',
          keybindings: [monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter],
          run: function() {
            runCode();
          }
        });

        // Add 'headers' to autocomplete
        monaco.languages.registerCompletionItemProvider('javascript', {
          provideCompletionItems: function(model, position) {
            return {
              suggestions: [
                {
                  label: 'headers',
                  kind: monaco.languages.CompletionItemKind.Variable,
                  insertText: 'headers',
                  detail: 'Authorization headers object',
                  documentation: 'Contains { "Authorization": "Bearer <token>" }'
                },
                {
                  label: 'fetch with headers',
                  kind: monaco.languages.CompletionItemKind.Snippet,
                  insertText: "const res = await fetch('\${1:url}', { headers })\\nconst data = await res.json()\\nconsole.log(data)",
                  insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
                  detail: 'Fetch with auth headers'
                }
              ]
            };
          }
        });
      });

      // OAuth config
      const config = {
        deviceUrl: ${JSON.stringify(deviceUrl)},
        tokenUrl: ${JSON.stringify(tokenUrl)},
        clientId: ${JSON.stringify(clientId)},
        clientSecret: ${JSON.stringify(clientSecret)},
        scope: ${JSON.stringify(scope)}
      };

      // Start device code flow
      authBtn.addEventListener('click', async () => {
        authBtn.disabled = true;
        authBtn.textContent = '⏳ Starting...';
        authStatus.textContent = '';
        authStatus.className = 'playground__auth-status';
        deviceCodeBox.style.display = 'none';

        try {
          // Request device code via proxy to bypass CORS
          const params = new URLSearchParams({
            _target_url: config.deviceUrl,
            client_id: config.clientId,
            scope: config.scope
          });

          const response = await fetch('/api/oauth/device', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json'
            },
            body: params.toString()
          });

          if (!response.ok) {
            throw new Error('Failed to get device code');
          }

          const data = await response.json();
          const { device_code, user_code, verification_uri, interval, expires_in } = data;

          // Show the code to the user
          deviceCodeBox.style.display = 'block';
          deviceCodeValue.textContent = user_code;
          deviceLink.href = verification_uri;
          deviceLink.textContent = verification_uri;
          authBtn.textContent = '⏳ Waiting for authorization...';
          authStatus.textContent = 'Enter the code above';
          authStatus.className = 'playground__auth-status playground__auth-status--info';

          // Copy code button
          copyCodeBtn.onclick = async () => {
            await navigator.clipboard.writeText(user_code);
            copyCodeBtn.textContent = 'Copied!';
            setTimeout(() => { copyCodeBtn.textContent = 'Copy Code'; }, 2000);
          };

          // Poll for token
          const pollInterval = (interval || 5) * 1000;
          const expiresAt = Date.now() + (expires_in || 900) * 1000;

          const poll = async () => {
            if (Date.now() > expiresAt) {
              onAuthError('Code expired. Please try again.');
              return;
            }

            try {
              const tokenParams = new URLSearchParams({
                _target_url: config.tokenUrl,
                client_id: config.clientId,
                device_code: device_code,
                grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
              });

              if (config.clientSecret) {
                tokenParams.append('client_secret', config.clientSecret);
              }

              const tokenResponse = await fetch('/api/oauth/token', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Accept': 'application/json'
                },
                body: tokenParams.toString()
              });

              const tokenData = await tokenResponse.json();

              if (tokenData.error === 'authorization_pending') {
                // Still waiting, poll again
                setTimeout(poll, pollInterval);
                return;
              }

              if (tokenData.error === 'slow_down') {
                // Slow down polling
                setTimeout(poll, pollInterval + 5000);
                return;
              }

              if (tokenData.error) {
                onAuthError(tokenData.error_description || tokenData.error);
                return;
              }

              if (tokenData.access_token) {
                token = tokenData.access_token;
                headers = { "Authorization": "Bearer " + token };
                onAuthSuccess();
                return;
              }

              // Unknown response, keep polling
              setTimeout(poll, pollInterval);

            } catch (err) {
              setTimeout(poll, pollInterval);
            }
          };

          // Start polling
          setTimeout(poll, pollInterval);

        } catch (err) {
          onAuthError(err.message);
        }
      });

      function onAuthSuccess() {
        deviceCodeBox.style.display = 'none';
        authBtn.textContent = '✓ Authenticated';
        authBtn.disabled = true;
        authStatus.textContent = '✓ Token received';
        authStatus.className = 'playground__auth-status playground__auth-status--success';
        runBtn.disabled = false;
        headersPreview.style.display = 'block';
        headersPreview.querySelector('.playground__headers-value').textContent =
          'const headers = { "Authorization": "Bearer ' + token.substring(0, 8) + '..." }';
      }

      function onAuthError(message) {
        deviceCodeBox.style.display = 'none';
        authBtn.textContent = '🔐 Authenticate with ${formula.label}';
        authBtn.disabled = false;
        authStatus.textContent = '✗ ' + message;
        authStatus.className = 'playground__auth-status playground__auth-status--error';
      }

      // Run code
      async function runCode() {
        if (!token) {
          appendOutput('Please authenticate first', 'error');
          return;
        }

        if (!editor) return;
        const code = editor.getValue();
        if (!code.trim()) return;

        output.innerHTML = '';
        runBtn.disabled = true;
        runBtn.textContent = '⏳ Running...';

        // Create a sandbox with headers available
        const sandbox = {
          headers: headers,
          fetch: window.fetch.bind(window),
          console: {
            log: (...args) => appendOutput(args.map(formatValue).join(' ')),
            error: (...args) => appendOutput(args.map(formatValue).join(' '), 'error'),
            info: (...args) => appendOutput(args.map(formatValue).join(' '), 'info'),
            warn: (...args) => appendOutput(args.map(formatValue).join(' '), 'error')
          }
        };

        try {
          const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
          const fn = new AsyncFunction('headers', 'fetch', 'console', code);
          await fn(sandbox.headers, sandbox.fetch, sandbox.console);
        } catch (err) {
          appendOutput('Error: ' + err.message, 'error');
        }

        runBtn.disabled = false;
        runBtn.textContent = '▶ Run';
      }

      function formatValue(val) {
        if (val === null) return 'null';
        if (val === undefined) return 'undefined';
        if (typeof val === 'object') {
          try {
            return JSON.stringify(val, null, 2);
          } catch (e) {
            return String(val);
          }
        }
        return String(val);
      }

      function appendOutput(text, type) {
        const line = document.createElement('div');
        line.className = 'playground__output-line' + (type ? ' playground__output-line--' + type : '');
        line.textContent = text;
        output.appendChild(line);
        output.scrollTop = output.scrollHeight;
      }

      runBtn.addEventListener('click', runCode);
    })();
  </script>
`;
  }

  return '<!DOCTYPE html>\n' +
'<html lang="en">\n' +
'<head>\n' +
'  <meta charset="UTF-8">\n' +
'  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
'  <title>' + title + '</title>\n' +
'  <meta name="description" content="' + description + '">\n' +
'  <meta name="keywords" content="authentication, oauth, ' + formula.id + ', ' + formula.label + ', agents, cli, runtime">\n' +
'  <meta name="author" content="Pedro Pinera">\n' +
'  <link rel="canonical" href="' + url + '">\n' +
'  <link rel="icon" type="image/png" href="/favicon.png">\n' +
'  <!-- Open Graph / Facebook -->\n' +
'  <meta property="og:type" content="article">\n' +
'  <meta property="og:url" content="' + url + '">\n' +
'  <meta property="og:title" content="' + title + '">\n' +
'  <meta property="og:description" content="' + description + '">\n' +
'  <meta property="og:site_name" content="Schlussel">\n' +
'  <meta property="og:image" content="https://schlussel.me/og/formulas/' + formula.id + '.png">\n' +
'  <meta property="og:image:width" content="1200">\n' +
'  <meta property="og:image:height" content="630">\n' +
'  <!-- Twitter -->\n' +
'  <meta name="twitter:card" content="summary_large_image">\n' +
'  <meta name="twitter:url" content="' + url + '">\n' +
'  <meta name="twitter:title" content="' + title + '">\n' +
'  <meta name="twitter:description" content="' + description + '">\n' +
'  <meta name="twitter:image" content="https://schlussel.me/og/formulas/' + formula.id + '.png">\n' +
'  <meta name="twitter:site" content="@pepicrft">\n' +
'  <meta name="twitter:creator" content="@pepicrft">\n' +
'  <!-- Additional SEO -->\n' +
'  <meta name="robots" content="index, follow">\n' +
'  <meta name="googlebot" content="index, follow">\n' +
'  <link rel="preconnect" href="https://fonts.googleapis.com">\n' +
'  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n' +
'  <link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">\n' +
'  <style>' + css + formulaPageCss + '</style>\n' +
'</head>\n' +
'<body>\n' +
'  <nav class="nav">\n' +
'    <div class="container nav__inner">\n' +
'      <a href="/" class="nav__brand">\n' +
'        <span class="nav__key">🔑</span>\n' +
'        <span>schlussel</span>\n' +
'      </a>\n' +
'      <button class="nav__toggle" aria-label="Toggle menu">\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'      </button>\n' +
'      <div class="nav__links">\n' +
'        <a href="/#features" class="nav__link">Features</a>\n' +
'        <a href="/#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="/#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/docs" class="nav__link">Docs</a>\n' +
'        <a href="/skill" class="nav__link">SKILL.md</a>\n' +
'        <a href="https://github.com/pepicrft/schlussel" class="nav__link">GitHub</a>\n' +
'      </div>\n' +
'    </div>\n' +
'  </nav>\n' +
'\n' +
'  <main class="formula-page">\n' +
'    <div class="container">\n' +
'      <div class="formula-header">\n' +
'        <div class="formula-header__breadcrumb">\n' +
'          <a href="/">Home</a> / <a href="/#formulas">Formulas</a> / ' + formula.label + '\n' +
'        </div>\n' +
'        <h1 class="formula-header__title">' + formula.label + '</h1>\n' +
'        <span class="formula-header__id">' + formula.id + '</span>\n' +
'        <p class="formula-header__desc">' + description + '</p>\n' +
'      </div>\n' +
'\n' +
'      <div class="formula-grid">\n' +
'        <div>\n' +
'          <div class="formula-section">\n' +
'            <h3 class="formula-section__title"><span class="formula-section__icon">🔐</span> Authentication Methods</h3>\n' +
'            ' + methodsHtml + '\n' +
'          </div>\n' +
'          ' + identityHtml + '\n' +
'        </div>\n' +
'        <div>\n' +
'          ' + apisHtml + '\n' +
'          ' + clientsHtml + '\n' +
'        </div>\n' +
'      </div>\n' +
'\n' +
       playgroundHtml + '\n' +
'      <a href="/#formulas" class="formula-back">← Back to all formulas</a>\n' +
'    </div>\n' +
'  </main>\n' +
'\n' +
'  <footer class="footer">\n' +
'    <div class="container">\n' +
'      <p>\n' +
'        Made with love by <a href="https://pepicrft.me">Pedro Pinera</a>.\n' +
'        Licensed under MIT.\n' +
'      </p>\n' +
'    </div>\n' +
'  </footer>\n' +
       playgroundScript + '\n' +
'  <script>\n' +
'    // Mobile nav toggle\n' +
'    const navToggle = document.querySelector(".nav__toggle");\n' +
'    const navLinks = document.querySelector(".nav__links");\n' +
'    navToggle.addEventListener("click", () => {\n' +
'      navToggle.classList.toggle("active");\n' +
'      navLinks.classList.toggle("open");\n' +
'    });\n' +
'  </script>\n' +
'</body>\n' +
'</html>';
}

const docsPageCss = `
.docs-page {
  padding: var(--space-lg) 0;
  min-height: calc(100vh - 200px);
}

.docs-header {
  text-align: center;
  margin-bottom: var(--space-lg);
}

.docs-header__title {
  font-size: clamp(2rem, 5vw, 3rem);
  margin-bottom: var(--space-sm);
}

.docs-header__desc {
  font-size: 1.1rem;
  max-width: 700px;
  margin: 0 auto var(--space-md);
  opacity: 0.9;
}

.docs-nav {
  display: flex;
  justify-content: center;
  gap: var(--space-sm);
  flex-wrap: wrap;
  margin-bottom: var(--space-lg);
}

.docs-nav__link {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-sm) var(--space-md);
  background: var(--white);
  border: var(--border-thick);
  border-radius: 12px;
  box-shadow: var(--shadow-cartoon);
  font-weight: 600;
  transition: all 0.2s ease;
}

.docs-nav__link:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
  color: var(--dark);
  background: var(--yellow);
}

.docs-nav__link--active {
  background: var(--yellow);
}

.docs-section {
  background: var(--white);
  padding: var(--space-lg);
  border-radius: 20px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  max-width: 900px;
  margin: 0 auto var(--space-lg);
}

.docs-section__title {
  font-size: 1.8rem;
  margin-bottom: var(--space-md);
  padding-bottom: var(--space-xs);
  border-bottom: 4px solid var(--yellow);
  display: flex;
  align-items: center;
  gap: var(--space-xs);
}

.docs-section__title a,
.docs-section__subtitle a {
  color: inherit;
  text-decoration: none;
}

.docs-section__title a:hover,
.docs-section__subtitle a:hover {
  color: var(--purple);
}

.docs-section__subtitle {
  font-size: 1.3rem;
  margin-top: var(--space-md);
  margin-bottom: var(--space-sm);
  color: var(--purple);
}

.docs-section p {
  margin-bottom: var(--space-sm);
  line-height: 1.7;
}

.docs-section ul, .docs-section ol {
  margin-bottom: var(--space-sm);
  padding-left: var(--space-md);
}

.docs-section li {
  margin-bottom: var(--space-xs);
  line-height: 1.6;
}

.docs-section pre {
  margin: var(--space-sm) 0;
}

.docs-table {
  width: 100%;
  border-collapse: collapse;
  margin: var(--space-sm) 0;
  font-size: 0.95rem;
}

.docs-table th,
.docs-table td {
  padding: var(--space-sm);
  text-align: left;
  border: 2px solid var(--dark);
}

.docs-table th {
  background: var(--yellow-light);
  font-weight: 700;
}

.docs-table tr:nth-child(even) {
  background: var(--cream);
}

.docs-table code {
  font-size: 0.85rem;
}

.docs-note {
  background: var(--yellow-light);
  padding: var(--space-sm) var(--space-md);
  border-radius: 12px;
  border: var(--border);
  margin: var(--space-sm) 0;
}

.docs-note__title {
  font-weight: 700;
  margin-bottom: var(--space-xs);
}
`;

const skillPageCss = `
.skill-page {
  padding: var(--space-lg) 0;
  min-height: calc(100vh - 200px);
}

.skill-header {
  text-align: center;
  margin-bottom: var(--space-lg);
}

.skill-header__title {
  font-size: clamp(2rem, 5vw, 3rem);
  margin-bottom: var(--space-sm);
}

.skill-header__desc {
  font-size: 1.1rem;
  max-width: 700px;
  margin: 0 auto var(--space-md);
  opacity: 0.9;
}

.skill-content {
  background: var(--white);
  padding: var(--space-lg);
  border-radius: 20px;
  border: var(--border-thick);
  box-shadow: var(--shadow-cartoon-lg);
  max-width: 900px;
  margin: 0 auto;
}

.skill-content h1 {
  display: none;
}

.skill-content h2 {
  font-size: 1.5rem;
  margin-top: var(--space-md);
  margin-bottom: var(--space-sm);
  padding-bottom: var(--space-xs);
  border-bottom: 3px solid var(--yellow);
}

.skill-content h3 {
  font-size: 1.2rem;
  margin-top: var(--space-sm);
  margin-bottom: var(--space-xs);
}

.skill-content p {
  margin-bottom: var(--space-sm);
}

.skill-content ul, .skill-content ol {
  margin-bottom: var(--space-sm);
  padding-left: var(--space-md);
}

.skill-content li {
  margin-bottom: var(--space-xs);
}

.skill-content pre {
  margin: var(--space-sm) 0;
}

.skill-copy-section {
  text-align: center;
  margin-top: var(--space-lg);
  padding-top: var(--space-md);
  border-top: 2px dashed var(--dark);
}

.skill-copy-section p {
  margin-bottom: var(--space-sm);
  font-size: 1rem;
  opacity: 0.85;
}

.skill-copy-btn {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-sm) var(--space-md);
  background: var(--yellow);
  border: var(--border-thick);
  border-radius: 12px;
  box-shadow: var(--shadow-cartoon);
  font-family: 'Fredoka', sans-serif;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
}

.skill-copy-btn:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
}

.skill-copy-btn:active {
  transform: translate(0, 0);
  box-shadow: 2px 2px 0px var(--dark);
}

.skill-raw-link {
  display: inline-block;
  margin-left: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  background: var(--white);
  border: var(--border-thick);
  border-radius: 12px;
  box-shadow: var(--shadow-cartoon);
  font-weight: 600;
  transition: all 0.2s ease;
}

.skill-raw-link:hover {
  transform: translate(-2px, -2px);
  box-shadow: var(--shadow-hover);
  color: var(--dark);
}
`;

export function renderSkillPage(markdown: string): string {
  const title = 'Schlussel Skill - Agent Instructions';
  const description = 'Instructions for agents to use Schlussel, the authentication runtime. Copy this into your agent configuration.';
  const url = 'https://schlussel.me/skill';

  const htmlContent = marked.parse(markdown);

  return '<!DOCTYPE html>\n' +
'<html lang="en">\n' +
'<head>\n' +
'  <meta charset="UTF-8">\n' +
'  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
'  <title>' + title + '</title>\n' +
'  <meta name="description" content="' + description + '">\n' +
'  <meta name="keywords" content="authentication, oauth, agents, cli, runtime, skill, instructions">\n' +
'  <meta name="author" content="Pedro Pinera">\n' +
'  <link rel="canonical" href="' + url + '">\n' +
'  <link rel="icon" type="image/png" href="/favicon.png">\n' +
'  <!-- Open Graph / Facebook -->\n' +
'  <meta property="og:type" content="article">\n' +
'  <meta property="og:url" content="' + url + '">\n' +
'  <meta property="og:title" content="' + title + '">\n' +
'  <meta property="og:description" content="' + description + '">\n' +
'  <meta property="og:site_name" content="Schlussel">\n' +
'  <meta property="og:image" content="https://schlussel.me/og/skill.png">\n' +
'  <meta property="og:image:width" content="1200">\n' +
'  <meta property="og:image:height" content="630">\n' +
'  <!-- Twitter -->\n' +
'  <meta name="twitter:card" content="summary_large_image">\n' +
'  <meta name="twitter:url" content="' + url + '">\n' +
'  <meta name="twitter:title" content="' + title + '">\n' +
'  <meta name="twitter:description" content="' + description + '">\n' +
'  <meta name="twitter:image" content="https://schlussel.me/og/skill.png">\n' +
'  <meta name="twitter:site" content="@pepicrft">\n' +
'  <meta name="twitter:creator" content="@pepicrft">\n' +
'  <!-- Additional SEO -->\n' +
'  <meta name="robots" content="index, follow">\n' +
'  <link rel="preconnect" href="https://fonts.googleapis.com">\n' +
'  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n' +
'  <link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">\n' +
'  <style>' + css + skillPageCss + '</style>\n' +
'</head>\n' +
'<body>\n' +
'  <nav class="nav">\n' +
'    <div class="container nav__inner">\n' +
'      <a href="/" class="nav__brand">\n' +
'        <span class="nav__key">🔑</span>\n' +
'        <span>schlussel</span>\n' +
'      </a>\n' +
'      <button class="nav__toggle" aria-label="Toggle menu">\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'      </button>\n' +
'      <div class="nav__links">\n' +
'        <a href="/#features" class="nav__link">Features</a>\n' +
'        <a href="/#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="/#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/docs" class="nav__link">Docs</a>\n' +
'        <a href="/skill" class="nav__link">SKILL.md</a>\n' +
'        <a href="https://github.com/pepicrft/schlussel" class="nav__link">GitHub</a>\n' +
'      </div>\n' +
'    </div>\n' +
'  </nav>\n' +
'\n' +
'  <main class="skill-page">\n' +
'    <div class="container">\n' +
'      <div class="skill-header">\n' +
'        <h1 class="skill-header__title">Agent Skill</h1>\n' +
'        <p class="skill-header__desc">\n' +
'          Copy these instructions into your agent configuration to enable Schlussel authentication.\n' +
'        </p>\n' +
'      </div>\n' +
'      <div class="skill-content" id="skill-content">\n' +
'        ' + htmlContent + '\n' +
'      </div>\n' +
'      <div class="skill-copy-section">\n' +
'        <p>Copy the raw markdown for use in your agent configuration:</p>\n' +
'        <button class="skill-copy-btn" id="copy-btn">Copy Markdown</button>\n' +
'        <a href="/skill.md" class="skill-raw-link">View Raw</a>\n' +
'      </div>\n' +
'    </div>\n' +
'  </main>\n' +
'\n' +
'  <footer class="footer">\n' +
'    <div class="container">\n' +
'      <p>\n' +
'        Made with love by <a href="https://pepicrft.me">Pedro Pinera</a>.\n' +
'        Licensed under MIT.\n' +
'      </p>\n' +
'    </div>\n' +
'  </footer>\n' +
'  <script>\n' +
'    const markdown = ' + JSON.stringify(markdown) + ';\n' +
'    const copyBtn = document.getElementById("copy-btn");\n' +
'    copyBtn.addEventListener("click", async () => {\n' +
'      try {\n' +
'        await navigator.clipboard.writeText(markdown);\n' +
'        copyBtn.textContent = "Copied!";\n' +
'        setTimeout(() => { copyBtn.textContent = "Copy Markdown"; }, 2000);\n' +
'      } catch (err) {\n' +
'        copyBtn.textContent = "Failed to copy";\n' +
'        setTimeout(() => { copyBtn.textContent = "Copy Markdown"; }, 2000);\n' +
'      }\n' +
'    });\n' +
'    // Mobile nav toggle\n' +
'    const navToggle = document.querySelector(".nav__toggle");\n' +
'    const navLinks = document.querySelector(".nav__links");\n' +
'    navToggle.addEventListener("click", () => {\n' +
'      navToggle.classList.toggle("active");\n' +
'      navLinks.classList.toggle("open");\n' +
'    });\n' +
'  </script>\n' +
'</body>\n' +
'</html>';
}

export function renderDocsPage(): string {
  const title = 'Documentation - Schlussel';
  const description = 'Complete documentation for Schlussel: formula specification, CLI commands, and API reference. Learn how to authenticate with any provider.';
  const url = 'https://schlussel.me/docs';

  return '<!DOCTYPE html>\n' +
'<html lang="en">\n' +
'<head>\n' +
'  <meta charset="UTF-8">\n' +
'  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
'  <title>' + title + '</title>\n' +
'  <meta name="description" content="' + description + '">\n' +
'  <meta name="keywords" content="schlussel, documentation, oauth, authentication, cli, formula, agents, api">\n' +
'  <meta name="author" content="Pedro Pinera">\n' +
'  <link rel="canonical" href="' + url + '">\n' +
'  <link rel="icon" type="image/png" href="/favicon.png">\n' +
'  <!-- Open Graph / Facebook -->\n' +
'  <meta property="og:type" content="article">\n' +
'  <meta property="og:url" content="' + url + '">\n' +
'  <meta property="og:title" content="' + title + '">\n' +
'  <meta property="og:description" content="' + description + '">\n' +
'  <meta property="og:site_name" content="Schlussel">\n' +
'  <meta property="og:image" content="https://schlussel.me/og/docs.png">\n' +
'  <meta property="og:image:width" content="1200">\n' +
'  <meta property="og:image:height" content="630">\n' +
'  <!-- Twitter -->\n' +
'  <meta name="twitter:card" content="summary_large_image">\n' +
'  <meta name="twitter:url" content="' + url + '">\n' +
'  <meta name="twitter:title" content="' + title + '">\n' +
'  <meta name="twitter:description" content="' + description + '">\n' +
'  <meta name="twitter:image" content="https://schlussel.me/og/docs.png">\n' +
'  <meta name="twitter:site" content="@pepicrft">\n' +
'  <meta name="twitter:creator" content="@pepicrft">\n' +
'  <!-- Additional SEO -->\n' +
'  <meta name="robots" content="index, follow">\n' +
'  <link rel="preconnect" href="https://fonts.googleapis.com">\n' +
'  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n' +
'  <link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">\n' +
'  <style>' + css + docsPageCss + '</style>\n' +
'</head>\n' +
'<body>\n' +
'  <nav class="nav">\n' +
'    <div class="container nav__inner">\n' +
'      <a href="/" class="nav__brand">\n' +
'        <span class="nav__key">🔑</span>\n' +
'        <span>schlussel</span>\n' +
'      </a>\n' +
'      <button class="nav__toggle" aria-label="Toggle menu">\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'        <span></span>\n' +
'      </button>\n' +
'      <div class="nav__links">\n' +
'        <a href="/#features" class="nav__link">Features</a>\n' +
'        <a href="/#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="/#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/docs" class="nav__link">Docs</a>\n' +
'        <a href="/skill" class="nav__link">SKILL.md</a>\n' +
'        <a href="https://github.com/pepicrft/schlussel" class="nav__link">GitHub</a>\n' +
'      </div>\n' +
'    </div>\n' +
'  </nav>\n' +
'\n' +
'  <main class="docs-page">\n' +
'    <div class="container">\n' +
'      <div class="docs-header">\n' +
'        <h1 class="docs-header__title">Documentation</h1>\n' +
'        <p class="docs-header__desc">\n' +
'          Everything you need to know about using Schlussel for authentication.\n' +
'        </p>\n' +
'      </div>\n' +
'\n' +
'      <nav class="docs-nav">\n' +
'        <a href="#formula-spec" class="docs-nav__link">📋 Formula Spec</a>\n' +
'        <a href="#cli" class="docs-nav__link">💻 CLI Reference</a>\n' +
'      </nav>\n' +
'\n' +
'      <!-- Formula Specification -->\n' +
'      <section class="docs-section" id="formula-spec">\n' +
'        <h2 class="docs-section__title"><a href="#formula-spec">📋 Formula Specification</a></h2>\n' +
'        <p>\n' +
'          Formulas are JSON files that describe how to authenticate with a provider. They contain\n' +
'          everything needed: OAuth endpoints, auth methods, API definitions, and optional public clients.\n' +
'        </p>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="root-fields"><a href="#root-fields">Root Fields</a></h3>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Field</th>\n' +
'              <th>Required</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>schema</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Version identifier. Must be <code>"v2"</code>.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>id</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Unique identifier (e.g., <code>github</code>, <code>stripe</code>). Used in CLI commands and storage keys.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>label</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Human-readable name for display.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>description</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Brief description of the provider and supported auth methods.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>methods</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Object defining authentication methods (see below).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>apis</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Object defining API endpoints.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>clients</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Array of public OAuth clients that can be used without registration.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>identity</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Hints for multi-account scenarios (label and hint text).</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="methods"><a href="#methods">Methods</a></h3>\n' +
'        <p>\n' +
'          Each method defines an authentication flow. Common method names:\n' +
'        </p>\n' +
'        <ul>\n' +
'          <li><code>authorization_code</code> - OAuth with browser redirect (has <code>endpoints.authorize</code> + <code>endpoints.token</code>)</li>\n' +
'          <li><code>device_code</code> - OAuth device flow (has <code>endpoints.device</code> + <code>endpoints.token</code>)</li>\n' +
'          <li><code>mcp_oauth</code> - MCP OAuth with dynamic registration (has <code>dynamic_registration</code> object)</li>\n' +
'          <li><code>api_key</code> / <code>personal_access_token</code> - Manual credential (has <code>script</code> with <code>copy_key</code>)</li>\n' +
'        </ul>\n' +
'\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Field</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>label</code></td>\n' +
'              <td>Human-readable name for the method.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>endpoints</code></td>\n' +
'              <td>OAuth endpoints: <code>authorize</code>, <code>token</code>, <code>device</code>, <code>registration</code>.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>scope</code></td>\n' +
'              <td>Space-separated OAuth scopes.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>register</code></td>\n' +
'              <td>Instructions for manual app registration (<code>url</code> and <code>steps</code> array).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>script</code></td>\n' +
'              <td>Array of steps guiding the user through authentication.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>dynamic_registration</code></td>\n' +
'              <td>RFC 7591 client registration parameters.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="script-steps"><a href="#script-steps">Script Steps</a></h3>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Type</th>\n' +
'              <th>Description</th>\n' +
'              <th>Value</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>open_url</code></td>\n' +
'              <td>User should open a URL</td>\n' +
'              <td>URL or <code>{placeholder}</code></td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>enter_code</code></td>\n' +
'              <td>User should enter a code</td>\n' +
'              <td>Code or <code>{user_code}</code></td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>copy_key</code></td>\n' +
'              <td>User should paste an API key</td>\n' +
'              <td>-</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>wait_for_callback</code></td>\n' +
'              <td>Wait for OAuth callback</td>\n' +
'              <td>-</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>wait_for_token</code></td>\n' +
'              <td>Poll for device code completion</td>\n' +
'              <td>-</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="placeholders"><a href="#placeholders">Placeholders</a></h3>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Placeholder</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>{authorize_url}</code></td>\n' +
'              <td>Full authorization URL with parameters</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>{verification_uri}</code></td>\n' +
'              <td>URL to enter device code</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>{verification_uri_complete}</code></td>\n' +
'              <td>URL with code pre-filled</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>{user_code}</code></td>\n' +
'              <td>Code user enters at verification URL</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="apis"><a href="#apis">APIs</a></h3>\n' +
'        <p>Each API defines an endpoint that can be called with tokens from specified methods:</p>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Field</th>\n' +
'              <th>Required</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>base_url</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>API base URL.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>auth_header</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>How to pass the token (e.g., <code>Authorization: Bearer {token}</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>methods</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Array of method names that produce valid tokens.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>docs_url</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Link to API documentation.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>spec_url</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Link to machine-readable spec.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>spec_type</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Type of spec: <code>openapi</code>, <code>graphql</code>, <code>asyncapi</code>.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="public-clients"><a href="#public-clients">Public Clients</a></h3>\n' +
'        <p>Clients bundled with the formula that users can use without registering their own OAuth app:</p>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Field</th>\n' +
'              <th>Required</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>name</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>Identifier for the client.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>id</code></td>\n' +
'              <td>Yes</td>\n' +
'              <td>OAuth client ID.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>secret</code></td>\n' +
'              <td>No</td>\n' +
'              <td>OAuth client secret (for confidential clients).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>source</code></td>\n' +
'              <td>No</td>\n' +
'              <td>URL where this client ID was found.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>methods</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Which methods this client supports (default: all OAuth methods).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>redirect_uri</code></td>\n' +
'              <td>No</td>\n' +
'              <td>Fixed redirect URI required by this client.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="storage-keys"><a href="#storage-keys">Storage Keys</a></h3>\n' +
'        <p>Tokens are stored using a conventional key format:</p>\n' +
'        <pre><code>{formula_id}:{method}:{identity}</code></pre>\n' +
'        <p>Examples:</p>\n' +
'        <ul>\n' +
'          <li><code>github:device_code:personal</code> - GitHub device code token for "personal" identity</li>\n' +
'          <li><code>linear:authorization_code:acme</code> - Linear OAuth token for "acme" workspace</li>\n' +
'          <li><code>stripe:api_key</code> - Stripe API key (no identity)</li>\n' +
'        </ul>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="example-formula"><a href="#example-formula">Example Formula</a></h3>\n' +
'        <pre><code>{\n' +
'  "schema": "v2",\n' +
'  "id": "github",\n' +
'  "label": "GitHub",\n' +
'  "description": "Authenticate with GitHub using OAuth device code flow...",\n' +
'  "apis": {\n' +
'    "rest": {\n' +
'      "base_url": "https://api.github.com",\n' +
'      "auth_header": "Authorization: Bearer {token}",\n' +
'      "docs_url": "https://docs.github.com/en/rest",\n' +
'      "spec_type": "openapi"\n' +
'    }\n' +
'  },\n' +
'  "clients": [\n' +
'    {\n' +
'      "name": "gh-cli",\n' +
'      "id": "178c6fc778ccc68e1d6a",\n' +
'      "secret": "34ddeff2b558a23d38fba...",\n' +
'      "source": "https://github.com/cli/cli",\n' +
'      "methods": ["device_code", "authorization_code"]\n' +
'    }\n' +
'  ],\n' +
'  "identity": {\n' +
'    "label": "Account",\n' +
'    "hint": "e.g., personal, work"\n' +
'  },\n' +
'  "methods": {\n' +
'    "device_code": {\n' +
'      "endpoints": {\n' +
'        "device": "https://github.com/login/device/code",\n' +
'        "token": "https://github.com/login/oauth/access_token"\n' +
'      },\n' +
'      "scope": "repo read:org gist",\n' +
'      "script": [\n' +
'        { "type": "open_url", "value": "{verification_uri}" },\n' +
'        { "type": "enter_code", "value": "{user_code}" },\n' +
'        { "type": "wait_for_token" }\n' +
'      ]\n' +
'    },\n' +
'    "personal_access_token": {\n' +
'      "register": {\n' +
'        "url": "https://github.com/settings/tokens/new",\n' +
'        "steps": ["Generate a new token", "Copy the token"]\n' +
'      },\n' +
'      "script": [\n' +
'        { "type": "copy_key", "note": "Paste your GitHub PAT" }\n' +
'      ]\n' +
'    }\n' +
'  }\n' +
'}</code></pre>\n' +
'      </section>\n' +
'\n' +
'      <!-- CLI Reference -->\n' +
'      <section class="docs-section" id="cli">\n' +
'        <h2 class="docs-section__title"><a href="#cli">💻 CLI Reference</a></h2>\n' +
'        <p>\n' +
'          The Schlussel CLI is the primary interface for authenticating with providers and managing tokens.\n' +
'        </p>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="installation"><a href="#installation">Installation</a></h3>\n' +
'        <pre><code># Using mise (recommended)\n' +
'mise use -g github:pepicrft/schlussel\n' +
'\n' +
'# Or build from source\n' +
'git clone https://github.com/pepicrft/schlussel\n' +
'cd schlussel && zig build</code></pre>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="commands"><a href="#commands">Commands</a></h3>\n' +
'\n' +
'        <h4 style="margin-top: var(--space-md); font-weight: 700;">schlussel run &lt;formula&gt;</h4>\n' +
'        <p>Authenticate with a provider and obtain a token.</p>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Option</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>-m, --method &lt;str&gt;</code></td>\n' +
'              <td>Authentication method (required if multiple methods available).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-c, --client &lt;str&gt;</code></td>\n' +
'              <td>Use a public client from the formula.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-r, --redirect-uri &lt;str&gt;</code></td>\n' +
'              <td>Redirect URI for auth code flow (default: <code>http://127.0.0.1:0/callback</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-f, --formula-json &lt;str&gt;</code></td>\n' +
'              <td>Load a custom formula JSON file.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--client-id &lt;str&gt;</code></td>\n' +
'              <td>Override OAuth client ID.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--client-secret &lt;str&gt;</code></td>\n' +
'              <td>Override OAuth client secret.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-s, --scope &lt;str&gt;</code></td>\n' +
'              <td>OAuth scopes (space-separated).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--credential &lt;str&gt;</code></td>\n' +
'              <td>Secret for non-OAuth methods (api_key).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-i, --identity &lt;str&gt;</code></td>\n' +
'              <td>Identity label for storage key (e.g., workspace name).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--open-browser &lt;true|false&gt;</code></td>\n' +
'              <td>Open the authorization URL automatically (default: true).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-j, --json</code></td>\n' +
'              <td>Emit machine-readable JSON output.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-n, --dry-run</code></td>\n' +
'              <td>Show auth steps and URLs without executing. Useful for previewing the flow.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <div class="docs-note">\n' +
'          <div class="docs-note__title">Auto-selection</div>\n' +
'          When a formula has a public client, Schlussel auto-selects it. If only one method is available, it is auto-selected too.\n' +
'        </div>\n' +
'\n' +
'        <h4 style="margin-top: var(--space-md); font-weight: 700;">schlussel token &lt;action&gt;</h4>\n' +
'        <p>Token management operations.</p>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Action</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>get</code></td>\n' +
'              <td>Retrieve a stored token. Requires <code>--key</code> or <code>--formula</code>.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>list</code></td>\n' +
'              <td>List all stored tokens. Can be filtered.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>delete</code></td>\n' +
'              <td>Delete a stored token. Requires <code>--key</code> or <code>--formula</code>.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <p><strong>Options:</strong></p>\n' +
'        <table class="docs-table">\n' +
'          <thead>\n' +
'            <tr>\n' +
'              <th>Option</th>\n' +
'              <th>Description</th>\n' +
'            </tr>\n' +
'          </thead>\n' +
'          <tbody>\n' +
'            <tr>\n' +
'              <td><code>-k, --key &lt;str&gt;</code></td>\n' +
'              <td>Full token storage key (e.g., <code>github:device_code:personal</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--formula &lt;str&gt;</code></td>\n' +
'              <td>Filter/query by formula ID (e.g., <code>github</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--method &lt;str&gt;</code></td>\n' +
'              <td>Filter/query by auth method (e.g., <code>device_code</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--identity &lt;str&gt;</code></td>\n' +
'              <td>Filter/query by identity label (e.g., <code>personal</code>).</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>--no-refresh</code></td>\n' +
'              <td>Disable auto-refresh. By default, OAuth2 tokens are refreshed if expired or expiring soon, using cross-process locking.</td>\n' +
'            </tr>\n' +
'            <tr>\n' +
'              <td><code>-j, --json</code></td>\n' +
'              <td>Output in JSON format.</td>\n' +
'            </tr>\n' +
'          </tbody>\n' +
'        </table>\n' +
'\n' +
'        <div class="docs-note">\n' +
'          <div class="docs-note__title">Auto-refresh with locking</div>\n' +
'          By default, <code>schlussel token get</code> automatically refreshes OAuth2 tokens that are expired or expiring soon. It acquires a cross-process lock before refreshing, ensuring that if multiple processes request the same token simultaneously, only one performs the refresh while others wait and receive the updated token. Use <code>--no-refresh</code> to disable this behavior.\n' +
'        </div>\n' +
'\n' +
'        <h3 class="docs-section__subtitle" id="examples"><a href="#examples">Examples</a></h3>\n' +
'        <pre><code># Authenticate with GitHub (auto-selects public client and method)\n' +
'schlussel run github\n' +
'\n' +
'# Preview auth flow without executing\n' +
'schlussel run github --dry-run\n' +
'\n' +
'# Authenticate with a specific method\n' +
'schlussel run github --method device_code\n' +
'\n' +
'# Use a specific public client\n' +
'schlussel run github --client gh-cli\n' +
'\n' +
'# Authenticate with Linear for a specific workspace\n' +
'schlussel run linear --method authorization_code --identity acme\n' +
'\n' +
'# Use a custom formula file\n' +
'schlussel run acme --formula-json ~/formulas/acme.json\n' +
'\n' +
'# Get JSON output for scripting\n' +
'schlussel run github --json\n' +
'\n' +
'# List all tokens\n' +
'schlussel token list\n' +
'\n' +
'# List tokens for a specific formula\n' +
'schlussel token list --formula github\n' +
'\n' +
'# Get token using key components (auto-refreshes if expiring)\n' +
'schlussel token get --formula github --method device_code\n' +
'\n' +
'# Get token without auto-refresh\n' +
'schlussel token get --formula github --method device_code --no-refresh\n' +
'\n' +
'# Get token as JSON\n' +
'schlussel token get --formula github --method device_code --json\n' +
'\n' +
'# Delete a token\n' +
'schlussel token delete --key github:device_code:personal</code></pre>\n' +
'      </section>\n' +
'    </div>\n' +
'  </main>\n' +
'\n' +
'  <footer class="footer">\n' +
'    <div class="container">\n' +
'      <p>\n' +
'        Made with love by <a href="https://pepicrft.me">Pedro Pinera</a>.\n' +
'        Licensed under MIT.\n' +
'      </p>\n' +
'    </div>\n' +
'  </footer>\n' +
'  <script>\n' +
'    // Mobile nav toggle\n' +
'    const navToggle = document.querySelector(".nav__toggle");\n' +
'    const navLinks = document.querySelector(".nav__links");\n' +
'    navToggle.addEventListener("click", () => {\n' +
'      navToggle.classList.toggle("active");\n' +
'      navLinks.classList.toggle("open");\n' +
'    });\n' +
'  </script>\n' +
'</body>\n' +
'</html>';
}
