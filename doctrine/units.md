# Units

How the agent fleet is organised: who commands, which staff lanes exist, what a rank means and how a call sign is read. The names borrow from army staff organisation so people can scan threads, the ledger and logs at a glance. Where the borrowing stops is stated at the end, so nobody builds on it.

Decisions: [owner decisions D1 to D8](https://github.com/deanjstone/agents/issues/1#issuecomment-6868378783), made on 14 Nov 2026 at 11:21 AEDT.

## Structure

No per-repo tier. Three levels and a small unit at the bottom:

```
Owner (commander)
  Aquila (XO)                       profile: staff-xo
    S-1   backlog admin
    S-2   research and intelligence
    S-3   operations, plans folded in
    S-4   logistics
    S-6   signal
      fire teams                    a builder and a reviewer
```

| Echelon | Doctrine meaning | Here | Today |
| ------- | ---------------- | ---- | ----- |
| Owner (commander) | Commands, sets intent, owns the decision | The human owner. The only customer, and the only release authority: Approve on the hub promotes `deploy` | Approve on the ops-hub card |
| XO | The commander's principal assistant and key staff integrator, who frees the commander from routine staff detail | Aquila names the orchestrator only; profile `staff-xo`. Other sessions are not Aquila | The direction and AFK orchestrator thread |
| S-1 | Personnel, headquarters management | Backlog upkeep: labels, waves, filing hygiene. A stretch of the doctrine, kept small | Hygiene work |
| S-2 | Intelligence for current operations and plans | Research: read sources, report cited findings | The research child |
| S-3 | Training, operations, plans and force development, integrating the operation as a whole | Running the work: slot workers. Plans (doctrinally G-5, which sits under the G-3 at our scale) is folded in here, so wayfinder maps and grilling belong to this lane | Slot workers, wayfinder |
| S-4 | Sustainment: supply, maintenance, transportation, services | Budget, host caps, memory and disk gates | The charter's resource gates |
| S-6 | Network operations, information services | Communication plumbing: loop-state, notice board, T3 peers, ops hub. Infrastructure, not an agent role | None as an agent |
| Fire team | The small self-contained fighting element | A builder plus a reviewer. An analogy, labelled as one: see [where the analogy breaks](#where-the-analogy-breaks) | Slot worker (builder), reviewer role to come |

The memory system, vault and notice board fit the doctrine's knowledge management officer (working through the XO) better than S-6. That is a note on the mapping, not a lane.

An approval thread has no obvious home. Leave it unmapped rather than force it.

## Ranks (our extension, not doctrine)

A rank is a short name for the permission envelope a profile runs with. It is **our extension**: army doctrine delegates by intent, it does not tier permissions by rank, and the names below are not army ranks. `lead` replaces `sergeant` because the owner asked for a non-military name.

The tiers, lowest to highest: **scout → specialist → lead → staff**.

| Rank | Envelope | Fits today |
| ---- | -------- | ---------- |
| scout | Read-only. Reports in its final message. No loop-state tools | Research child, hygiene child |
| specialist | Writes in its own worktree and pushes or merges its own change. No live changes | Slot worker, reviewer |
| lead | A specialist that may also launch children and steer workers | None today. Reserved |
| staff | Runs a lane with loop-state tools and a lease | Aquila (`direction` and `afk`) |

A rank names an envelope and nothing else. The profile states what it may do; the rank is the label people read. A change to a profile's `rank`, `lane`, `tools` or `model` is an authority change and needs the owner's approval.

## Call signs

Section first, with no unit prefix: `S<section>-<n>`.

| Call sign | Reads as |
| --------- | -------- |
| `S2-1` | The first research child (S-2) |
| `S1-1` | The first hygiene child (S-1) |
| `S3-4` | Slot 4 (S-3) |

- Aquila is the XO and is addressed by name, not by a section call sign.
- Add a unit prefix only when a second host gets its own unit.
- **Call signs carry no authority.** They exist for people scanning threads, the ledger and logs. A rank grants an envelope; a call sign grants nothing.
- The scheme is ours. No call-sign doctrine could be read, so it does not claim to follow military convention.

## Doctrine sources and their limits

- [FM 6-0, Commander and Staff Organization and Operations (5 May 2014)](https://home.army.mil/wood/download_file/view/6638/1525): command post, XO (¶2-32), coordinating staff (¶2-37 and the duty paragraphs), no S-5 below division (¶2-36), knowledge management officer (¶3-15).
- [FM 3-21.8, The Infantry Rifle Platoon and Squad (28 Mar 2007)](https://usu.edu/military-science/files/tools-for-cadets/the-infantry-rifle-platoon-and-squad.pdf): squad of two fire teams (¶1-82), the four-role fire team (¶1-72, ¶1-73).

These are the 2014 and 2007 editions and may differ from current doctrine. Current ATP 3-21.8, ADP 6-0 and any call-sign convention were not readable. The research is in [agents/1](https://github.com/deanjstone/agents/issues/1#issuecomment-6780366131), section 2.

## Where the analogy breaks

Stated so nobody builds on it.

1. **Our scarce thing is tokens and context, and every echelon summarises.** A summary passed across an echelon loses detail. Doctrine's own rule of intent held "two echelons lower" (FM 6-0 ¶9-75) argues for fewer echelons, hence no deep chain.
2. **Agents start blank.** Mission command assumes shared understanding. A brief is the whole of the commander's intent, so the original issue text travels verbatim into every brief.
3. **Staff in doctrine may hold decision authority within intent (FM 6-0 ¶2-3). The remaining difference is write access.** A research child is read-only and a slot worker writes, so they are separate profiles.
4. **A report here is a claim.** Doctrine has staff assistance visits and inspections too. What differs is that ours verifies mechanically (`verify-claim.sh`, CI), outside the chain.
5. **S-1 is a stretch.** "Headquarters management" covers backlog upkeep only loosely. Do not extend it.
6. **Rank flavour alone is unproven.** No study of rank text was found. A rank earns its place as a permission envelope, not as flavour.
7. **The fire team is our buddy-pair analogy.** The doctrinal fire team has four members with complementary roles. A builder plus a reviewer is a pair, not that.
8. **The commander is also the only customer and the release authority.** That is a local fact of this system, not doctrine.
