import { listFormulas, formulas, Formula } from './formulas-data';

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

@media (max-width: 768px) {
  :root {
    --space-lg: 3rem;
    --space-xl: 4rem;
  }

  .nav__links { display: none; }

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
  const url = 'https://schlussel.pepicrft.me';

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
'      <div class="nav__links">\n' +
'        <a href="#features" class="nav__link">Features</a>\n' +
'        <a href="#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/api/formulas" class="nav__link">API</a>\n' +
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
'                Schlussel checks for existing tokens, refreshes if needed (with locking),\n' +
'                or guides the user through OAuth. All based on the formula for that platform.\n' +
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
'          <h2 class="reflection__title">The Narrow Waist for Agents</h2>\n' +
'          <p class="reflection__text">\n' +
'            Not every service on the internet exposes an API. Many are hesitant, watching how\n' +
'            a new layer of agentic applications and LLMs might extract value from their platforms\n' +
'            the same way tech giants once built empires on top of telecommunications infrastructure.\n' +
'            The fear is real: become the "dumb pipe" while others capture the margin.\n' +
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
'        </div>\n' +
'      </div>\n' +
'    </section>\n' +
'\n' +
'    <section class="formulas" id="formulas">\n' +
'      <div class="container">\n' +
'        <h2 class="section__title">Built-in Formulas</h2>\n' +
'        <p class="formulas__intro">\n' +
'          Schlussel ships with formulas for popular platforms. Each formula knows\n' +
'          the OAuth endpoints, scopes, and even includes public client credentials\n' +
'          when available. Zero config for common cases.\n' +
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
`;

export function renderFormulaPage(formula: Formula): string {
  const title = formula.label + ' Authentication - Schlussel';
  const description = formula.description || 'Authenticate with ' + formula.label + ' using Schlussel, the auth runtime for agents.';
  const url = 'https://schlussel.pepicrft.me/formulas/' + formula.id;

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
      '<p style="margin-bottom: var(--space-sm); opacity: 0.85;">These clients are bundled with the formula. You can use them without registering your own OAuth application.</p>' +
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
'  <meta property="og:image" content="https://schlussel.pepicrft.me/og/formulas/' + formula.id + '.png">\n' +
'  <meta property="og:image:width" content="1200">\n' +
'  <meta property="og:image:height" content="630">\n' +
'  <!-- Twitter -->\n' +
'  <meta name="twitter:card" content="summary_large_image">\n' +
'  <meta name="twitter:url" content="' + url + '">\n' +
'  <meta name="twitter:title" content="' + title + '">\n' +
'  <meta name="twitter:description" content="' + description + '">\n' +
'  <meta name="twitter:image" content="https://schlussel.pepicrft.me/og/formulas/' + formula.id + '.png">\n' +
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
'      <div class="nav__links">\n' +
'        <a href="/#features" class="nav__link">Features</a>\n' +
'        <a href="/#how-it-works" class="nav__link">How it works</a>\n' +
'        <a href="/#formulas" class="nav__link">Formulas</a>\n' +
'        <a href="/api/formulas" class="nav__link">API</a>\n' +
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
'</body>\n' +
'</html>';
}
