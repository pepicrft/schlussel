import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { ImageResponse } from 'workers-og';
import { formulas, getFormula, listFormulas, searchFormulas } from './formulas-data';
import { renderHomepage, renderFormulaPage } from './html';

const app = new Hono();

// Enable CORS for API routes
app.use('/api/*', cors());

// Homepage
app.get('/', (c) => {
  return c.html(renderHomepage());
});

// Formula pages
app.get('/formulas/:id', (c) => {
  const id = c.req.param('id');
  const formula = getFormula(id);

  if (!formula) {
    return c.notFound();
  }

  return c.html(renderFormulaPage(formula));
});

// Sitemap for search engines
app.get('/sitemap.xml', (c) => {
  const baseUrl = 'https://schlussel.pepicrft.me';
  const formulaList = listFormulas();

  const urls = [
    { loc: baseUrl, priority: '1.0', changefreq: 'weekly' },
    ...formulaList.map(f => ({
      loc: baseUrl + '/formulas/' + f.id,
      priority: '0.8',
      changefreq: 'monthly'
    }))
  ];

  const xml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    urls.map(u =>
      '  <url>\n' +
      '    <loc>' + u.loc + '</loc>\n' +
      '    <changefreq>' + u.changefreq + '</changefreq>\n' +
      '    <priority>' + u.priority + '</priority>\n' +
      '  </url>'
    ).join('\n') + '\n' +
    '</urlset>';

  c.header('Content-Type', 'application/xml');
  return c.body(xml);
});

// Robots.txt for search engines
app.get('/robots.txt', (c) => {
  const txt = 'User-agent: *\n' +
    'Allow: /\n' +
    '\n' +
    'Sitemap: https://schlussel.pepicrft.me/sitemap.xml\n';

  c.header('Content-Type', 'text/plain');
  return c.body(txt);
});

// OG Image for homepage
app.get('/og.png', async () => {
  const html = `
    <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; width: 1200px; height: 630px; background: #FFFBF0; font-family: sans-serif;">
      <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; background: #FFFFFF; padding: 60px 80px; border-radius: 32px; border: 6px solid #2D3436; box-shadow: 12px 12px 0px #2D3436;">
        <div style="display: flex; align-items: center; gap: 20px; margin-bottom: 10px;">
          <span style="font-size: 72px; font-weight: 700; color: #2D3436;">schlussel</span>
        </div>
        <div style="display: flex; font-size: 24px; color: #2D3436; opacity: 0.7; margin-bottom: 30px;">
          github.com/pepicrft/schlussel
        </div>
        <div style="display: flex; background: #A66CFF; color: white; padding: 12px 24px; border-radius: 50px; font-size: 24px; font-weight: 600; border: 4px solid #2D3436; box-shadow: 4px 4px 0px #2D3436; margin-bottom: 30px;">
          Auth Runtime for Agents
        </div>
        <div style="display: flex; background: #2D3436; color: #FFE135; padding: 20px 40px; border-radius: 16px; font-size: 32px; font-family: monospace; border: 4px solid #2D3436;">
          curl + schlussel is all you need
        </div>
      </div>
    </div>
  `;

  return new ImageResponse(html, {
    width: 1200,
    height: 630,
  });
});

// OG Image for formula pages
app.get('/og/formulas/:id', async (c) => {
  let id = c.req.param('id');
  // Strip .png extension if present
  if (id.endsWith('.png')) {
    id = id.slice(0, -4);
  }
  const formula = getFormula(id);

  if (!formula) {
    return c.notFound();
  }

  const methods = Object.keys(formula.methods).slice(0, 4).join(' • ');
  const hasClients = formula.clients && formula.clients.length > 0;

  const html = `
    <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; width: 1200px; height: 630px; background: #FFFBF0; font-family: sans-serif;">
      <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; background: #FFFFFF; padding: 50px 70px; border-radius: 32px; border: 6px solid #2D3436; box-shadow: 12px 12px 0px #2D3436; max-width: 1000px;">
        <div style="display: flex; align-items: center; gap: 16px; margin-bottom: 20px;">
          <span style="font-size: 28px; font-weight: 600; color: #2D3436;">github.com/pepicrft/schlussel</span>
        </div>
        <div style="display: flex; font-size: 64px; font-weight: 700; color: #2D3436; margin-bottom: 20px; text-align: center;">
          ${formula.label} formula
        </div>
        <div style="display: flex; background: #FFF59D; padding: 10px 20px; border-radius: 8px; font-size: 24px; font-family: monospace; border: 3px solid #2D3436; margin-bottom: 20px;">
          ${formula.id}
        </div>
        <div style="display: flex; gap: 12px; flex-wrap: wrap; justify-content: center; margin-bottom: 20px;">
          ${methods ? `<div style="display: flex; font-size: 22px; color: #2D3436; opacity: 0.8;">${methods}</div>` : ''}
        </div>
        ${hasClients ? `
          <div style="display: flex; align-items: center; gap: 10px; background: #26DE81; color: #2D3436; padding: 10px 20px; border-radius: 50px; font-size: 20px; font-weight: 600; border: 3px solid #2D3436;">
            <span style="width: 12px; height: 12px; background: #2D3436; border-radius: 50%;"></span>
            Contains public client
          </div>
        ` : ''}
      </div>
    </div>
  `;

  return new ImageResponse(html, {
    width: 1200,
    height: 630,
  });
});

// API: List all formulas
app.get('/api/formulas', (c) => {
  const query = c.req.query('q');
  if (query) {
    const results = searchFormulas(query);
    return c.json({
      formulas: results.map(f => ({ id: f.id, label: f.label })),
      total: results.length,
      query
    });
  }
  return c.json({
    formulas: listFormulas(),
    total: Object.keys(formulas).length
  });
});

// API: Get a specific formula
app.get('/api/formulas/:id', (c) => {
  const id = c.req.param('id');
  const formula = getFormula(id);

  if (!formula) {
    return c.json({ error: 'Formula not found' }, 404);
  }

  return c.json(formula);
});

// API: Get all formulas (full data)
app.get('/api/formulas.json', (c) => {
  return c.json(formulas);
});

export default app;
