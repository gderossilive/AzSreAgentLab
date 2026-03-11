# Grubify Source Code

The Grubify app is sourced from <https://github.com/dm-chelupati/grubify>.

## Setup

Clone the Grubify repository into this directory:

```bash
cd demos/GrubifyIncidentLab/src
git clone https://github.com/dm-chelupati/grubify.git
```

The `post-provision.sh` script builds the container image in ACR (cloud-side)
from `src/grubify/GrubifyApi/`. No local Docker is required.

If the `src/grubify/` directory is missing when `azd up` runs, the Container App
will use a placeholder image and you can build later with:

```bash
./scripts/post-provision.sh --skip-build
```
