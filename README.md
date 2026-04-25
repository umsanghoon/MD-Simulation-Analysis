# MD-Simulation-Analysis

## Overview

This repository provides a complete workflow for molecular dynamics (MD) simulation and analysis of collagen-mimetic peptide systems with dynamic covalent linkers.

Simulations are performed using Schrödinger Desmond on GPU HPC systems, and results are analyzed using R-based scripts.

---

## Scientific Background and Molecular Design

This study focuses on collagen-mimetic systems constructed from NPG (Asn–Pro–Gly) trimer units forming a triple helix.

Each system consists of:
- 3 chains (triple helix)
- 30 residues per chain
- 90 total residues

Each chain contains repeating NPG trimers, resulting in 9 linker positions per chain.

The system is designed such that:
- N-terminal = amine
- C-terminal = aldehyde

These termini enable formation of dynamic covalent linkers, including:
- Imine
- Hydrated imine
- Pyrimidinone

---

## Model Construction Strategy

Two approaches were explored:

### 1. Crystal Structure-Based (1K6F)

- Source: PDB 1K6F (PPG triple helix)
- 6 chains → reduced to 3 chains
- Mutated PPG → NPG
- Linkers introduced

Result:
- Structure too tightly packed
- Severe distortion during MD
- Unstable simulations

→ This approach was discarded

---

### 2. AF3-Based Model (Final)

- Backbone obtained from AlphaFold3
- Modified in Schrödinger BioLuminate
- Linker chemistry introduced directly

Advantage:
- More relaxed structure
- Stable during MD

---

## Model Definition

Models are defined based on linker composition.

Example:

NPG6-4

This indicates:
- 6 imine linkers
- 4 pyrimidinone linkers

(per chain)

Additional variants:

NPG6-4_A3a

Where:
- NPG6-4 = composition
- A3a = linker spatial arrangement

---

## Scientific Objective

The goal is to determine how linker composition and arrangement influence:

- Triple helix stability
- Structural compactness
- Hydrogen bonding network

Hypothesis:
Mixed linker systems (imine + pyrimidinone) provide enhanced stability.

---

## Simulation Workflow

1. MD Simulation (Desmond, HPC)
2. Data extraction (RMSD, Rg, H-bond)
3. Visualization (R)

---

## Directory Structure

MD-Simulation-Analysis/
├── desmond/
│   ├── hpc_run/run_NPG.cmd
│   └── extraction/
│       ├── 01_extract_RMSD.sh
│       ├── 02_extract_Rg.sh
│       └── 03_extract_Hbond.sh
├── plotting_R/
│   ├── RMSD.R
│   ├── Rg.R
│   └── H-bond.R
└── README.md

---

## File Naming Convention

YYYY-MM-DD_STRUCTURE_VARIANT_rX_ANALYSIS.ext

Example:
2026-04-20_NPG6-4_A3a_r1_RMSD.dat

---

## Key Analysis Metrics

RMSD:
- Measures structural deviation

Rg:
- Measures compactness

H-bonds:
- Intra-chain vs inter-chain interactions

---

## Reproducibility

Run simulation:
llsubmit run_NPG.cmd

Extract data:
bash 01_extract_RMSD.sh
bash 02_extract_Rg.sh
bash 03_extract_Hbond.sh

Plot:
source("RMSD.R")
source("Rg.R")
source("H-bond.R")

---

## Author

Sang Hoon Um
