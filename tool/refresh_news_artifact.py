#!/usr/bin/env python3
"""Validate app artifact provenance and safely extract without changing app bytes."""
import argparse
import json
from pathlib import Path, PurePosixPath
import tarfile


def candidate_runs(runs, head_sha):
    selected = []
    for run in sorted(runs, key=lambda r: r.get('updatedAt', ''), reverse=True):
        if (run.get('headSha') == head_sha and run.get('headBranch') == 'main'
                and run.get('conclusion') == 'success' and run.get('event') in ('push', 'workflow_dispatch', 'schedule', 'workflow_run')):
            selected.append(int(run['databaseId']))
    if not selected:
        raise ValueError('No successfully deployed artifact for current main; skip rather than roll back')
    return selected

def select_run(runs, head_sha):
    return candidate_runs(runs, head_sha)[0]


def extract(archive, destination):
    destination = Path(destination)
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Destination must be empty')
    with tarfile.open(archive, 'r:*') as tar:
        members = tar.getmembers()
        if sum(m.size for m in members) > 500_000_000:
            raise ValueError('Artifact too large')
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or '\\' in member.name or not (member.isfile() or member.isdir()):
                raise ValueError('Unsafe archive member')
        names = {str(PurePosixPath(m.name)) for m in members}
        if not {'index.html', 'shike-sw.js', 'news.json', 'version.json'} <= names:
            raise ValueError('Not a news-enabled application artifact')
        destination.mkdir(parents=True, exist_ok=True)
        tar.extractall(destination, members=members, filter='data')
    worker = (destination / 'shike-sw.js').read_text()
    marker = 'const BUILD = '
    build = json.loads(worker.split(marker, 1)[1].split(';', 1)[0])
    if any(r['path'] == 'news.json' for r in build['resources']):
        raise ValueError('News snapshot must not be in app cache manifest')


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    select = sub.add_parser('select')
    select.add_argument('runs'); select.add_argument('sha')
    select.add_argument('--refresh-runs')
    select.add_argument('--all', action='store_true')
    unpack = sub.add_parser('extract')
    unpack.add_argument('archive'); unpack.add_argument('destination')
    args = parser.parse_args()
    if args.command == 'select':
        runs = json.loads(Path(args.runs).read_text())
        if args.refresh_runs:
            runs += json.loads(Path(args.refresh_runs).read_text())
        print('\n'.join(map(str, candidate_runs(runs, args.sha))) if args.all else select_run(runs, args.sha))
    else:
        extract(args.archive, args.destination)

if __name__ == '__main__':
    main()
