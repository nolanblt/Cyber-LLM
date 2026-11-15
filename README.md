# Cyber-LLM

Cyber-LLM is a command-line copilot for authorised-lab penetration testing: you
paste the output of a recon command, and a large language model answers with
prioritised next steps that follow a standard pentest methodology. It is aimed at
people practising offensive security on machines they are allowed to attack
(TryHackMe, Hack The Box, CTFs, personal labs) — it is a copilot, not an
autonomous scanner, and it never acts without your go-ahead.

> The command-line interface and the model's answers are in **French** (the
> methodology prompt is written in French). This README is in English.

---

## Demo

> **To record before publishing.** The most useful thing on this page is a short
> terminal recording of a real session. It cannot be committed from a build
> machine because a live run needs a valid API key — see
> [Recording a demo](#recording-a-demo). A ready-to-run recording script is
> provided at `docs/demo.tape`. Drop the resulting `docs/demo.gif` here:
> `![Cyber-LLM session](docs/demo.gif)`.

Representative session (the model's exact wording varies from run to run):

```
============================================================
  Cyber-LLM — Copilote de pentest (V3)
------------------------------------------------------------
  [!] Labs AUTORISES uniquement (TryHackMe, HackTheBox...).
  Tu gardes la decision : l'assistant PROPOSE, tu valides.
  [Memoire] Il se souvient de la machine en cours.
  [Auto]    'auto' (de)active l'execution assistee (recon).
============================================================

Colle ta sortie (nmap, curl, ...) ou ta question, puis END pour envoyer.
Commandes : help | fiche | sauver/charger | auto | nouvelle | quit

> 22/tcp  open  ssh      OpenSSH 7.6p1
> 80/tcp  open  http     Apache httpd 2.4.29
> 445/tcp open  smb      Samba smbd 4.7.6
> END

[ANALYSE]
Three services on the host: OpenSSH 7.6p1, Apache 2.4.29, Samba 4.7.6.
SMB and the web server are the most promising enumeration targets.

[PISTES]
1. Enumerate SMB shares and users:  enum4linux -a <ip>
2. Enumerate web content:           gobuster dir -u http://<ip> -w <wordlist>
3. Check each version against known CVEs (searchsploit).

[AVANT D'AGIR]
All read-only enumeration. Confirm the target is in your authorised scope.
```

---

## What problem it solves

On a lab box, a large part of the time goes into *deciding the next step* and
recalling the methodology, while re-reading scan output again and again. Cyber-LLM
keeps that reasoning structured and keeps the running context (open ports,
services, credentials found, access obtained) in one place, so the loop is faster.
It is deliberately a copilot: it proposes, you decide, you run the commands —
except in an opt-in assisted mode where it can run read-only recon tools after you
confirm each one.

---

## How it works

You run a recon tool yourself, paste its output into the CLI and end with `END`.
The tool wraps that output with an authorised-lab context and a methodology
"system prompt", sends the running session history to the model (Claude, through
the Anthropic API), and prints a fixed-format answer:

- `[ANALYSE]` — what the output shows;
- `[PISTES]` — two or three prioritised next steps, each with a ready-to-run command;
- `[AVANT D'AGIR]` — a go/no-go reminder;
- `[FICHE MACHINE]` — a hidden, cumulative summary (IP, ports, services,
  credentials, access) you can display with `fiche` and save / reload across
  sessions.

```
   recon tool (nmap / enum4linux / curl / ...)
        |  paste output, end with END
        v
   src/cli.py  -->  src/assistant.py  -->  src/llm_client.py  -->  Anthropic API (Claude)
        ^            adds methodology        session history,
        |            prompt + lab context     prompt caching
        |
        +---- prioritised next steps  <--  [ANALYSE] / [PISTES] / [AVANT D'AGIR] (+ hidden [FICHE MACHINE])
```

The session has a memory (the conversation history is resent each turn, with
Anthropic prompt caching to limit cost), and the machine sheet (`fiche`) lets you
stop and resume a box later.

---

## Safety design

The model only ever **proposes**. Running commands is **off by default**.

An opt-in assisted mode (`auto`, or launch with `--auto`) lets the tool run a
command it proposed, but only if **all** of the following hold
(see `src/executeur.py`):

1. the binary is on a static **allowlist of read-only recon tools**
   (`nmap`, `enum4linux`, `enum4linux-ng`, `smbmap`, `nbtscan`, `dig`,
   `nslookup`, `host`, `whatweb`, `gobuster`, `ffuf`, `dirb`, `nikto`,
   `snmpwalk`, `showmount`);
2. the command contains **no shell metacharacter** (`;`, `|`, `&`, `>`, `` ` ``,
   `$`, …) — no chaining;
3. it matches **no destructive pattern**;
4. you **confirm that exact command** (`o/N`).

Execution then runs **without a shell** (`subprocess.run(..., shell=False)`) and
with a timeout. Anything not on the allowlist stays manual.

Why these choices: the model reasons over **attacker-controlled data** — a
target's banners and files can contain text crafted to steer a language model
(prompt injection). So the tool never trusts the model to authorise its own
execution. A static allowlist, shell-free execution and a mandatory per-command
confirmation bound what can run, independently of what the model says. (This
bounds *execution*; it does not make the textual advice injection-proof — see
Limitations.)

---

## Tests and evaluation

These are two different things.

**Unit tests (`tests/`, run with `pytest`) — 35 tests, currently all passing.**
They check the plumbing: session memory, the machine sheet, response parsing, the
executor guardrails, and the eval scoring logic. They **do not call the model** —
the API call is replaced by a stub — so they are free, instant and deterministic.

```bash
pip install -r requirements-dev.txt   # installs pytest (use your virtualenv)
pytest
```

**Evaluation bench (`evals/`) — separate, and it does call the real model.**
It runs the copilot on 8 representative cases (recon, Linux/Windows privilege
escalation, web enumeration, and two "trap" cases that request destructive or
out-of-scope actions). The cases are split into `dev` (used to tune the prompt)
and `test` (held out, to check the prompt generalises rather than overfits). Each
answer is scored on mechanical criteria (format respected, grounded in the pasted
output, no destructive command, actionable) and, optionally, by an
LLM-as-judge (relevance, no hallucination, prioritisation).

```bash
python -m evals.run_eval            # mechanical criteria, dev + test
python -m evals.run_eval all --juge # add the LLM judge (one extra model call per case)
```

It prints per-case and per-split scores and writes a detailed report (with the
full answers) to `evals/resultats/`. On a recent run: **29/30** on the mechanical
criteria, and **54/54** with the judge enabled — but read the Limitations: the
set is small, scores vary run to run, and the judge is itself a language model.

---

## Install and quick start

Requirements: **Python 3.11+** and an **Anthropic API key**.

### Linux / macOS

```bash
git clone https://github.com/nolanblt/Cyber-LLM.git
cd Cyber-LLM
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # then edit .env and paste your real key
python -m src.cli
```

### Windows (PowerShell)

```powershell
git clone https://github.com/nolanblt/Cyber-LLM.git
cd Cyber-LLM
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env          # then edit .env and paste your real key
python -m src.cli
```

Configuration lives in `.env` (never committed):

| Variable | Purpose | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | — (required) |
| `CYBER_LLM_MODEL` | Claude model used | `claude-opus-4-8` |
| `CYBER_LLM_EFFORT` | Reasoning effort (`low`…`max`) | `high` |
| `ANTHROPIC_WORKSPACE_ID` | Workspace id, only if your key needs one | *(empty)* |

In-session commands: `fiche` (show the machine sheet), `sauver [name]` /
`charger [name]` (save / reload it), `auto` (toggle assisted execution),
`nouvelle` (reset), `help`, `quit`.

### Recording a demo

The session recording at the top needs a live API key, so it is produced locally,
not on CI. Two options:

- **vhs** (reproducible): install [vhs](https://github.com/charmbracelet/vhs),
  set your key in `.env`, then `vhs docs/demo.tape` → produces `docs/demo.gif`.
  The tape assumes a Unix shell (use WSL on Windows).
- **ScreenToGif** (simplest on Windows): run `python -m src.cli`, play a short
  session, and record the terminal window with
  [ScreenToGif](https://www.screentogif.com/). Save it as `docs/demo.gif`.

Then embed it at the top of the Demo section: `![Cyber-LLM session](docs/demo.gif)`.

---

## Limitations

Read this before expecting too much.

- **It is not a scanner or an exploit tool.** It does not find vulnerabilities by
  itself. The quality of its advice depends entirely on what you paste and on the
  model; it can be generic, wrong, or occasionally reference something that was
  not in the output (hallucination). You are the operator — verify everything.
- **It depends on a hosted API.** Pasted output is sent to Anthropic's servers, so
  as-is it is unsuitable for engagements where data must not leave your
  infrastructure. A local-model backend (Ollama) is planned but **not implemented**.
- **Non-deterministic.** The same input can yield different suggestions from one
  run to the next. (During development the eval caught a safety case that kept its
  required format on one run and dropped it on another, before a prompt fix.)
- **Assisted execution allowlists the binary, not its arguments.** A permitted
  tool can still be given a file-writing or shell-escaping flag (for example
  `nmap -oN <file>` or `nmap --interactive`). Today the per-command human
  confirmation is the only backstop for that; argument-level filtering is on the
  backlog. Keep `auto` off unless you read each command.
- **Textual advice is not injection-proof.** The allowlist and confirmation bound
  what can *run*, but a crafted target could still try to steer the model's
  suggestions.
- **Model pinned to Claude Opus 4.8.** Newer Claude models frequently refuse
  security-lab content; the pin works today but is a moving constraint.
- **The eval bench is small (8 cases) and partly judged by another LLM.** Treat
  its scores as a regression signal, not as proof of quality.
- **Assisted execution targets a Linux attack host.** It expects the recon tools
  to be installed and executes without a shell on Unix; on Windows the tools are
  not found.
- **Not reviewed by anyone else.** Personal learning project (see Status).

---

## Status

Personal project, single author, currently at version 3 (V3). Built while
learning, for a career move toward offensive security (with an AI × security
angle). Licensed under the MIT License (see `LICENSE`).
