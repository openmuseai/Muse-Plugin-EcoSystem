#!/usr/bin/env python3
"""Validate review snapshot, executable backlog, local links and optional Git handoff ancestry."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--current',action='store_true');p.add_argument('--git',action='store_true');a=p.parse_args()
D=Path(__file__).resolve().parents[1];W=D.parents[5]
def read(path):return json.loads((D/path).read_text())
snapshot=read('progress/20261107/status.json');ledger=read('siyuan-collaboration-parity.json');backlog=read('development-backlog.json');handoff=read('handoff-commits.json')
assert snapshot['families']['total']==50 and not snapshot['fullParityReady']
assert sum(snapshot['families']['implementation'].values())==50
assert snapshot['families']['fullyAccepted']==0
assert snapshot['activeSlice']['state']=='verification_pending' and snapshot['activeSlice']['executionFreeze']=='not-created'
assert snapshot['platforms']['android']=={'unrun':50}
if a.current:
    assert dict(collections.Counter(x['implementation'] for x in ledger['requirements']))==snapshot['families']['implementation']
    assert dict(collections.Counter(x['completion'] for x in ledger['requirements']))==snapshot['families']['completion']
    for platform,counts in snapshot['platforms'].items():assert dict(collections.Counter(x['verification'][platform] for x in ledger['requirements']))==counts
ids={x['id'] for x in ledger['requirements']};tickets=backlog['tickets'];by_id={x['id']:x for x in tickets}
assert len(tickets)==len(by_id)==22
states=set(backlog['statusDefinitions']);covered=set();visiting=set();done=set()
def walk(id):
    assert id not in visiting,('Dependency cycle',id)
    if id in done:return
    visiting.add(id)
    for dep in by_id[id]['dependsOn']:assert dep in by_id;walk(dep)
    visiting.remove(id);done.add(id)
for ticket in tickets:
    assert ticket['state'] in states and ticket['acceptance'] and ticket['ownerRole']
    assert set(ticket['families'])<=ids
    if ticket['id']!='SDR-22':covered.update(ticket['families'])
    walk(ticket['id'])
    if ticket['state'] in {'ready','done'}:assert all(by_id[d]['state']=='done' for d in ticket['dependsOn'])
    for target in ticket['evidence']:assert (D/target).exists(),target
assert covered==ids,sorted(ids-covered)
assert by_id['SDR-01']['state']=='verification_pending'
assert by_id['SDR-02']['state']=='verification_pending' and by_id['SDR-02']['progress']['cleanNativeWebCloudBuild']=='not-run'
assert backlog['platformPolicy']['android']['state']=='deferred' and backlog['platformPolicy']['android']['requiresExplicitUserChange']
assert backlog['nextResumeTask']=='SDR-01'
for state,key in [('in_progress','implementation'),('verification_pending','verification')]:
    assert sum(by_id[id]['state']==state for id in backlog['activeWork'])<=backlog['wipLimits'][key]
expected_commits=snapshot['postReviewUpdates']['codeAndEvidenceLocalCommits']
assert handoff['recordedCommits']==len(handoff['commits'])==expected_commits
assert len({(x['repository'],x['sha']) for x in handoff['commits']})==expected_commits
assert dict(collections.Counter(x['repository'] for x in handoff['commits']))==handoff['countsByRepository']
assert handoff['localOnly'] and not handoff['pushed']
for name in ['49-PROGRESS-REVIEW-20261107.zh-CN.md','50-REVISED-DEVELOPMENT-PLAN.zh-CN.md','51-DEVELOPMENT-HANDOFF.zh-CN.md']:
    text=(D/name).read_text()
    for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)',text):
        if re.match(r'^[a-zA-Z]+:',target) or target.startswith('#'):continue
        target=target.split('#',1)[0];assert (D/target).exists(),(name,target)
for platform in ['macos','ios']:
    report=read('progress/20261107/p25/'+platform+'/result.json');assert report['status']=='passed-formula-slice' and (report['primaryChecks'],report['freshProcessChecks'])==(9,3)
checks=read('progress/20261107/checks.json');assert len(checks['checks'])==24 and all(x['exitCode']==0 for x in checks['checks']) and checks['fullParityGateExitCode']==1
export=read('progress/20261107/git-export-checks.json');assert len(export['checks'])==25 and all(x['exitCode']==0 for x in export['checks']) and export['fullBuildReproduction']=='not-run'
client=read('progress/20261107/client-tests.json');assert len(client)==8 and all(x['exitCode']==0 for x in client)
folder=D/'progress/20261107';manifest=read('progress/20261107/manifest.json')
for item in manifest['files']:
    file=folder/item['path'];assert file.resolve().is_relative_to(folder.resolve()) and file.is_file() and not file.is_symlink()
    assert hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256'],item['path']
assert {str(f.relative_to(folder)) for f in folder.rglob('*') if f.is_file()}-{'manifest.json'}=={e['path'] for e in manifest['files']}
if a.git:
    roots={'Muse-Plugin-Ecosystem':W/'Muse-Plugin-Ecosystem','Muse-Client':W/'Muse-Client','AppFlowy-Cloud':W/'Muse-Server/AppFlowy-Cloud'}
    for commit in handoff['commits']:
        assert re.fullmatch('[0-9a-f]{40}',commit['sha'])
        subprocess.run(['git','cat-file','-e',commit['sha']+'^{commit}'],cwd=roots[commit['repository']],check=True,capture_output=True)
        subprocess.run(['git','merge-base','--is-ancestor',commit['sha'],'HEAD'],cwd=roots[commit['repository']],check=True,capture_output=True)
print(f'Development handoff valid: 22 work packages cover all 50 families; {expected_commits} prior scoped commits; full product NOT COMPLETE')
