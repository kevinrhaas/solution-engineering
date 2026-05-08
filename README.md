# Solution Engineering Repository

This repository is a working collection of Pentaho solution-engineering assets, deployment tooling, demos, automation, and prototype applications.

It is not a single product. It is a mixed engineering workspace that includes reusable deployment scripts, sample content, internal-style experiments, and supporting utilities across analytics, AI, cloud, and operations workflows.

## Repository Notes

- Expect active development and uneven levels of polish across folders.
- Some areas are production-oriented deployment assets; others are proofs of concept or scratchpad projects.
- The public copy of this repository is a sanitized snapshot. Secret-bearing values and a small number of sensitive artifacts were removed before publishing.

## Key Areas

### Deployment and Platform Operations

- [pentaho-docker-deploy](./pentaho-docker-deploy/) - EC2-based Pentaho deployment automation.
- [pentaho-11-docker-deploy](./pentaho-11-docker-deploy/) - newer Pentaho 11 deployment assets, environment files, and operational helpers.
- [pentaho-ops-console](./pentaho-ops-console/) - operations console and supporting data assets.
- [airflow](./airflow/) - Airflow-oriented orchestration examples and supporting configuration.
- [openshift](./openshift/) - OpenShift-related deployment material.

### Data, Analytics, and AI Workstreams

- [aperture](./aperture/) - AI-assisted lead generation, model integration, and example transformations.
- [pdc-analysis](./pdc-analysis/) - PDC analytics schemas, content, dashboards, and utility scripts.
- [pdc-automation](./pdc-automation/) - shell-driven automation around ingestion, profiling, aggregation, and collection workflows.
- [pentaho-content](./pentaho-content/) - exported Pentaho content, datasources, and home-content snapshots.
- [gcp](./gcp/) - Google Cloud related examples and supporting assets.
- [databricks](./databricks/) - Databricks integration experiments and sample commands.

### Applications and Utilities

- [glossary](./glossary/) - glossary generation and management app.
- [tts](./tts/) - text-to-speech tooling.
- [jeopardy](./jeopardy/) - small quiz/game assets and static web files.
- [cadquery-web](./cadquery-web/) - CADQuery-related web work.
- [openclaw](./openclaw/) - agent and automation experiments.

### Archive and Reference Material

- [archive](./archive/) - older deployment and experiment snapshots kept for reference.
- Top-level SQL, PDF, and test files are retained as working artifacts rather than curated package contents.

## Getting Started

Start with the README inside the specific area you care about. Good entry points are:

- [pentaho-docker-deploy/README.md](./pentaho-docker-deploy/README.md)
- [pentaho-11-docker-deploy/README.md](./pentaho-11-docker-deploy/README.md)
- [glossary/README.md](./glossary/README.md)

If a folder does not have a README, treat it as a working project area and inspect the scripts, environment samples, and adjacent files before running anything.

## Top-Level Layout

```text
solution-engineering/
|-- airflow/
|-- aperture/
|-- archive/
|-- cadquery-web/
|-- databricks/
|-- gcp/
|-- glossary/
|-- jeopardy/
|-- openclaw/
|-- openshift/
|-- pdc-analysis/
|-- pdc-automation/
|-- pentaho-11-docker-deploy/
|-- pentaho-content/
|-- pentaho-docker-deploy/
|-- pentaho-ops-console/
|-- tts/
`-- README.md
```

## Usage Guidance

- Review scripts before running them, especially anything that provisions cloud infrastructure or writes to external systems.
- Expect environment-specific configuration in `.env`, `.ini`, JSON, and shell-variable files.
- Do not assume example credentials or endpoints in historical content are valid or intended for reuse.
