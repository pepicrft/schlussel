#!/usr/bin/env node

import { readdir, readFile, writeFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const formulasDir = join(__dirname, '../../src/formulas');
const outputFile = join(__dirname, '../src/formulas-data.ts');

async function buildFormulas() {
  const files = await readdir(formulasDir);
  const jsonFiles = files.filter(f => f.endsWith('.json'));

  const formulas = {};

  for (const file of jsonFiles) {
    const content = await readFile(join(formulasDir, file), 'utf-8');
    const formula = JSON.parse(content);
    formulas[formula.id] = formula;
  }

  const output = `// Auto-generated from formulas/*.json
// Do not edit manually - run "pnpm run build:formulas" to regenerate

export const formulas: Record<string, Formula> = ${JSON.stringify(formulas, null, 2)};

export interface Formula {
  schema: string;
  id: string;
  label: string;
  description?: string;
  apis?: Record<string, ApiDef>;
  clients?: Client[];
  identity?: { label?: string; hint?: string };
  methods: Record<string, MethodDef>;
}

export interface ApiDef {
  base_url: string;
  auth_header: string;
  docs_url?: string;
  spec_url?: string;
  spec_type?: string;
  methods?: string[];
}

export interface Client {
  name: string;
  id: string;
  secret?: string;
  source?: string;
  methods?: string[];
}

export interface MethodDef {
  label?: string;
  endpoints?: Record<string, string>;
  scope?: string;
  register?: { url: string; steps: string[] };
  script?: Array<{ type: string; value?: string; note?: string }>;
  dynamic_registration?: Record<string, unknown>;
}

export function getFormula(id: string): Formula | undefined {
  return formulas[id];
}

export function listFormulas(): Array<{ id: string; label: string }> {
  return Object.values(formulas).map(f => ({ id: f.id, label: f.label }));
}

export function searchFormulas(query: string): Formula[] {
  const q = query.toLowerCase();
  return Object.values(formulas).filter(f =>
    f.id.toLowerCase().includes(q) ||
    f.label.toLowerCase().includes(q) ||
    Object.keys(f.methods).some(m => m.toLowerCase().includes(q))
  );
}
`;

  await writeFile(outputFile, output);
  console.log('Generated ' + outputFile + ' with ' + Object.keys(formulas).length + ' formulas');
}

buildFormulas().catch(console.error);
