#!/usr/bin/env node
/**
 * Export canonical ABIs from Foundry artifacts to the frontend.
 * Usage: node scripts/export-abis.mjs
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const outDir = join(root, 'out')
const frontendAbiDir = join(root, '..', 'frontend', 'lib', 'abis')

const exportsList = [
  { artifact: 'RobinVault.sol/RobinVault.json', exportName: 'robinVaultAbi', file: 'robin-vault.ts' },
  { artifact: 'StrategyBase.sol/StrategyBase.json', exportName: 'strategyAbi', file: 'strategy.ts' },
  { artifact: 'GrowthStrategy.sol/GrowthStrategy.json', exportName: 'growthStrategyAbi', file: 'growth-strategy.ts' },
  {
    artifact: 'ConcentratedLiquidityStrategy.sol/ConcentratedLiquidityStrategy.json',
    exportName: 'clStrategyAbi',
    file: 'cl-strategy.ts',
  },
  { artifact: 'RobinAccountant.sol/RobinAccountant.json', exportName: 'robinAccountantAbi', file: 'robin-accountant.ts' },
]

mkdirSync(frontendAbiDir, { recursive: true })

for (const { artifact, exportName, file } of exportsList) {
  const artifactPath = join(outDir, artifact)
  const data = JSON.parse(readFileSync(artifactPath, 'utf8'))
  const content = `// AUTO-GENERATED from robin-harvest-contracts/out/${artifact}\n// Run: cd robin-harvest-contracts && node scripts/export-abis.mjs\nexport const ${exportName} = ${JSON.stringify(data.abi, null, 2)} as const\n`
  writeFileSync(join(frontendAbiDir, file), content)
  console.log(`Exported ${exportName} -> frontend/lib/abis/${file}`)
}
