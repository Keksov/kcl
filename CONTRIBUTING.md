# Contributing to kcl

kcl is a submodule of [kbool](https://github.com/Keksov/kbool), and its tests
need the whole tree. The full guide — the one test command, what CI checks,
what the verdicts mean, the house rules — is
[kbool's CONTRIBUTING.md](https://github.com/Keksov/kbool/blob/main/CONTRIBUTING.md).

Work in the `kcl/` folder of a kbool checkout
(`git clone --recurse-submodules https://github.com/Keksov/kbool.git`) and send
the pull request here, against `main`.

* Each unit's suite is `<unit>/tests/` — gate suite id `kcl/<unit>` (or just
  `<unit>`). `tests/` (suite id `kcl`) checks the unit shape of every unit
  ([README §3](README.md#3-running-the-tests)).
* From the kbool root: `bash ktests/tools/gate.sh kcl/<unit> kcl`;
  `bash ktests/tools/gate.sh --changed` also picks the units that `kk.uses` yours.
* Every unit keeps [the kcl contract](README.md#1-the-kcl-contract); a new unit
  follows [Adding a unit](README.md#adding-a-unit) (a row in `tests/kcl_units.sh`
  and a stub `tests/NNN_<unit>.sh`).
* A unit's API and deviations: `<unit>/README.md`; its plan, ledger and
  coverage notes: `docs/dev/<unit>/`.
* `tests/002_Bash51Hazards.sh` checks the bash 5.1 floor over the non-test code.
* CI: `.github/workflows/ci.yml` runs kbool's 13 rows with your PR in place of
  kcl; the checks are named `kbool / linux (debian 13)` and so on.
