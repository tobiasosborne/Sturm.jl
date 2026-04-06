#!/usr/bin/env node
// Fetch paywalled quantum simulation papers via headed Playwright browser (TIB VPN required).
// Usage: node docs/literature/quantum_simulation/fetch_paywalled.mjs
//
// 1. Ensure TIB VPN is active.
// 2. Script opens headed Chromium and navigates to a publisher page.
// 3. Click through any Cloudflare/CAPTCHA challenges in the browser window.
// 4. Script auto-detects passage and fetches all PDFs.

import { chromium } from '/home/tobiasosborne/Projects/qvls-sturm/viz/node_modules/playwright/index.mjs';
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { resolve } from 'path';

const BASE = resolve(import.meta.dirname);

const PAPERS = [
  // --- Paywalled papers (need TIB VPN) ---
  {
    id: 'Trotter_ProcAMS_1959',
    file: 'product_formulas/Trotter_ProcAMS_10_545_1959.pdf',
    // JSTOR — TIB should have access
    url: 'https://www.jstor.org/stable/pdf/2033649.pdf',
    fallback: 'https://doi.org/10.2307/2033649',
    desc: 'Trotter 1959 — On the product of semi-groups of operators',
  },
  {
    id: 'Feynman_IJTP_1982',
    file: 'surveys_complexity/Feynman_IJTP_21_467_1982.pdf',
    url: 'https://link.springer.com/content/pdf/10.1007/BF02650179.pdf',
    fallback: 'https://doi.org/10.1007/BF02650179',
    desc: 'Feynman 1982 — Simulating physics with computers',
  },
  {
    id: 'Suzuki_JMP_1985',
    file: 'product_formulas/Suzuki_JMP_26_601_1985.pdf',
    url: 'https://pubs.aip.org/aip/jmp/article-pdf/26/4/601/19176519/601_1_online.pdf',
    fallback: 'https://doi.org/10.1063/1.526596',
    desc: 'Suzuki 1985 — Decomposition formulas of exponential operators',
  },
  {
    id: 'Suzuki_PLA_1990',
    file: 'product_formulas/Suzuki_PLA_146_319_1990.pdf',
    url: 'https://www.sciencedirect.com/science/article/pii/037596019090962N/pdf',
    fallback: 'https://doi.org/10.1016/0375-9601(90)90962-N',
    desc: 'Suzuki 1990 — Fractal decomposition of exponential operators',
  },

  // --- Papers with known free PDFs (try these first, no VPN needed) ---
  {
    id: 'Suzuki_JMP_1991',
    file: 'product_formulas/Suzuki_JMP_32_400_1991.pdf',
    url: 'https://chaosbook.org/library/SuzukiJMP91.pdf',
    fallback: null,
    desc: 'Suzuki 1991 — General theory of fractal path integrals',
  },
  {
    id: 'Lloyd_Science_1996',
    file: 'surveys_complexity/Lloyd_Science_273_1073_1996.pdf',
    url: 'https://fab.cba.mit.edu/classes/862.22/notes/computation/Lloyd-1996.pdf',
    fallback: 'https://doi.org/10.1126/science.273.5278.1073',
    desc: 'Lloyd 1996 — Universal quantum simulators',
  },
];

async function waitForAccess(page, timeoutMs = 180000) {
  console.log('Waiting for access (Cloudflare / institutional login)...');
  console.log('>>> If you see a challenge, click it in the browser window <<<');
  console.log(`>>> Timeout: ${timeoutMs / 1000}s <<<\n`);

  try {
    // Wait until we're past any challenge page
    await page.waitForFunction(
      () => {
        // Signals we're on a real publisher page, not a challenge
        return (
          document.querySelector('meta[name="citation_title"]') ||
          document.querySelector('meta[name="dc.title"]') ||
          document.querySelector('.article-title') ||
          document.querySelector('#article') ||
          document.title.includes('PDF') ||
          document.contentType === 'application/pdf' ||
          // JSTOR
          document.querySelector('.pdfjs-viewer') ||
          // Springer
          document.querySelector('.c-article-title') ||
          // Generic: page loaded and no challenge detected
          (document.body &&
            document.body.innerText.length > 500 &&
            !document.body.innerText.includes('Checking your browser'))
        );
      },
      { timeout: timeoutMs }
    );

    console.log(`Page loaded: "${await page.title()}"`);
    await new Promise((r) => setTimeout(r, 2000));
    return true;
  } catch (_) {
    return false;
  }
}

async function main() {
  // Ensure all output directories exist
  for (const paper of PAPERS) {
    const dir = resolve(BASE, paper.file, '..');
    mkdirSync(dir, { recursive: true });
  }

  console.log('Launching HEADED Chromium (persistent profile)...');
  console.log('TIB VPN should be active for paywalled papers.\n');

  const userDataDir = resolve(BASE, '.browser-profile');
  mkdirSync(userDataDir, { recursive: true });

  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
    viewport: { width: 1280, height: 900 },
  });
  const page = context.pages()[0] || (await context.newPage());

  // Try free PDFs first (no challenge expected)
  const freePapers = PAPERS.filter(
    (p) => p.id === 'Suzuki_JMP_1991' || p.id === 'Lloyd_Science_1996'
  );
  const paywalledPapers = PAPERS.filter(
    (p) => p.id !== 'Suzuki_JMP_1991' && p.id !== 'Lloyd_Science_1996'
  );

  let downloaded = 0;
  let failed = 0;
  let skipped = 0;

  async function fetchPaper(paper, needsChallenge) {
    const outPath = resolve(BASE, paper.file);
    if (existsSync(outPath)) {
      console.log(`SKIP ${paper.id}: already exists`);
      skipped++;
      return;
    }

    console.log(`\n--- ${paper.desc} ---`);
    process.stdout.write(`FETCH ${paper.id} ... `);

    try {
      // Navigate to the URL
      await page.goto(paper.url, {
        waitUntil: 'domcontentloaded',
        timeout: 30000,
      });

      if (needsChallenge) {
        const passed = await waitForAccess(page);
        if (!passed) {
          console.log('TIMEOUT waiting for access');
          // Try fallback DOI
          if (paper.fallback) {
            console.log(`Trying fallback: ${paper.fallback}`);
            await page.goto(paper.fallback, {
              waitUntil: 'domcontentloaded',
              timeout: 30000,
            });
            const passed2 = await waitForAccess(page);
            if (!passed2) {
              console.log('FAIL (fallback also timed out)');
              failed++;
              return;
            }
          } else {
            failed++;
            return;
          }
        }
      }

      // Try to get the PDF via direct request (uses session cookies)
      const response = await page.request.get(paper.url, { timeout: 60000 });

      if (response.status() !== 200) {
        console.log(`FAIL (HTTP ${response.status()})`);
        failed++;
        return;
      }

      const body = await response.body();
      const header = body.slice(0, 5).toString();
      if (header !== '%PDF-') {
        // Maybe we got an HTML page with a PDF link — try to find it
        console.log(`Got HTML instead of PDF. Trying to find PDF link...`);

        // Look for PDF download link on the page
        const pdfLink = await page.evaluate(() => {
          const links = Array.from(document.querySelectorAll('a[href]'));
          const pdfLink = links.find(
            (a) =>
              a.href.includes('.pdf') ||
              a.href.includes('/pdf/') ||
              a.textContent.toLowerCase().includes('download pdf') ||
              a.textContent.toLowerCase().includes('full text pdf')
          );
          return pdfLink ? pdfLink.href : null;
        });

        if (pdfLink) {
          console.log(`Found PDF link: ${pdfLink}`);
          const pdfResp = await page.request.get(pdfLink, { timeout: 60000 });
          if (pdfResp.status() === 200) {
            const pdfBody = await pdfResp.body();
            if (pdfBody.slice(0, 5).toString() === '%PDF-') {
              writeFileSync(outPath, pdfBody);
              console.log(`OK (${(pdfBody.length / 1024).toFixed(0)} KB)`);
              downloaded++;
              return;
            }
          }
        }

        console.log('FAIL (could not find PDF)');
        failed++;
        return;
      }

      writeFileSync(outPath, body);
      console.log(`OK (${(body.length / 1024).toFixed(0)} KB)`);
      downloaded++;

      await new Promise((r) => setTimeout(r, 2000));
    } catch (e) {
      console.log(`ERROR: ${e.message}`);
      failed++;
    }
  }

  // Phase 1: free papers (no challenge needed)
  console.log('=== Phase 1: Free PDFs (no VPN needed) ===\n');
  for (const paper of freePapers) {
    await fetchPaper(paper, false);
  }

  // Phase 2: paywalled papers (may need challenge click)
  if (paywalledPapers.length > 0) {
    console.log('\n=== Phase 2: Paywalled papers (TIB VPN) ===');
    console.log('Navigate to the first publisher page to trigger any challenges.\n');

    // Trigger institutional access by visiting a publisher page
    await page.goto(paywalledPapers[0].fallback || paywalledPapers[0].url, {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
    await waitForAccess(page);

    for (const paper of paywalledPapers) {
      await fetchPaper(paper, true);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }

  console.log(
    `\n\nDone: ${downloaded} downloaded, ${failed} failed, ${skipped} skipped`
  );
  await context.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
