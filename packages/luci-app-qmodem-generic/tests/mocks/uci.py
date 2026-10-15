#!/usr/bin/env python3
"""Mock `uci` for off-device testing.

Config comes from $MOCK_UCI_CONFIG, a JSON file shaped like:

  { "qmodem":  { "modem0": { "name": "MOCK", "network": "mock0", ... } },
    "network": { "mockwan": { "modem_config": "modem0" } } }

Supported invocations used by the QModem scripts:
  uci show <package>
  uci [-q] get <package>.<section>.<option>
  uci add_list / set / commit / delete  (recorded, then no-op)
"""

import json
import os
import sys

CFG = os.environ.get('MOCK_UCI_CONFIG')


def load():
    if CFG and os.path.exists(CFG):
        try:
            with open(CFG, 'r', encoding='utf-8') as fh:
                return json.load(fh)
        except ValueError:
            pass
    return {}


def quote(value):
    if isinstance(value, bool):
        return "'%s'" % ('1' if value else '0')
    return "'%s'" % str(value)


def main():
    argv = sys.argv[1:]
    quiet = False
    while argv and argv[0] in ('-q', '-c'):
        if argv[0] == '-c':
            argv = argv[2:]
            continue
        quiet = True
        argv = argv[1:]

    if not argv:
        return 1
    cmd = argv[0]
    cfg = load()

    if cmd == 'show':
        pkg = argv[1] if len(argv) > 1 else None
        if pkg and pkg.count('.') == 2:
            p, section, key = pkg.split('.')
            opts = cfg.get(p, {}).get(section, {})
            if key not in opts:
                return 1
            val = opts[key]
            values = val if isinstance(val, list) else [val]
            sys.stdout.write('%s=%s\n' % (pkg, ' '.join(quote(v) for v in values)))
            return 0
        pkgs = [pkg] if pkg else list(cfg)
        emitted = False
        for p in pkgs:
            if p not in cfg:
                continue
            sys.stdout.write("%s=package\n" % p)
            for section, options in cfg[p].items():
                sys.stdout.write('%s.%s=%s\n' % (p, section,
                                                 options.get('.type', 'section')))
                for key, value in options.items():
                    if key.startswith('.'):
                        continue
                    if isinstance(value, list):
                        sys.stdout.write('%s.%s.%s=%s\n' % (
                            p, section, key, ' '.join(quote(v) for v in value)))
                    else:
                        sys.stdout.write('%s.%s.%s=%s\n' % (p, section, key, quote(value)))
                    emitted = True
        return 0 if emitted or not quiet else 1

    if cmd == 'get':
        parts = argv[1].split('.')
        if len(parts) == 2:
            pkg, section = parts
            value = cfg.get(pkg, {}).get(section, {}).get('.type')
            if not value:
                return 1
            sys.stdout.write('%s\n' % value)
            return 0
        if len(parts) != 3:
            return 1
        pkg, section, option = parts
        try:
            value = cfg[pkg][section][option]
        except KeyError:
            return 1
        if isinstance(value, list):
            sys.stdout.write(' '.join(str(v) for v in value) + '\n')
        elif isinstance(value, bool):
            sys.stdout.write(('1' if value else '0') + '\n')
        else:
            sys.stdout.write('%s\n' % value)
        return 0

    # mutating commands are recorded so tests can assert they ran
    log = os.environ.get('MOCK_UCI_LOG')
    if log:
        with open(log, 'a', encoding='utf-8') as fh:
            fh.write(' '.join(argv) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
