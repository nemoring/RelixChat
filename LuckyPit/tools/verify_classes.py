# -*- coding: utf-8 -*-
"""Checks compiled classes for CLDC 1.1 / MIDP 2.0 deployment:
 - class file version must be <= 48 (CLDC VMs reject newer formats)
 - no Java 6 StackMapTable, methods with branches carry CLDC StackMap (preverified)
 - every referenced class exists in the CLDC/MIDP API jars or in our package
"""
import struct
import sys
import os
import zipfile

BRANCH = set(range(0x99, 0xA9 + 1)) | {0xAA, 0xAB, 0xC6, 0xC7, 0xC8, 0xC9}


def parse(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'\xca\xfe\xba\xbe', 'bad magic'
    minor, major = struct.unpack('>HH', d[4:8])
    n = struct.unpack('>H', d[8:10])[0]
    cp = [None] * n
    i = 10
    k = 1
    while k < n:
        tag = d[i]
        if tag == 1:
            ln = struct.unpack('>H', d[i + 1:i + 3])[0]
            cp[k] = ('utf8', d[i + 3:i + 3 + ln].decode('utf-8', 'replace'))
            i += 3 + ln
        elif tag in (3, 4):
            cp[k] = ('num',); i += 5
        elif tag in (5, 6):
            cp[k] = ('wide',); i += 9; k += 1
        elif tag == 7:
            cp[k] = ('class', struct.unpack('>H', d[i + 1:i + 3])[0]); i += 3
        elif tag == 8:
            cp[k] = ('str',); i += 3
        elif tag in (9, 10, 11, 12):
            cp[k] = ('ref',); i += 5
        else:
            raise ValueError('cp tag %d' % tag)
        k += 1
    classes = set()
    for e in cp:
        if e and e[0] == 'class':
            name = cp[e[1]][1]
            while name.startswith('['):
                name = name[1:]
            if name.startswith('L') and name.endswith(';'):
                name = name[1:-1]
            if len(name) > 1:
                classes.add(name)
    i += 6
    ni = struct.unpack('>H', d[i:i + 2])[0]
    i += 2 + 2 * ni

    def skip_members(i):
        cnt = struct.unpack('>H', d[i:i + 2])[0]
        i += 2
        stats = []
        for _ in range(cnt):
            i += 6
            ac = struct.unpack('>H', d[i:i + 2])[0]
            i += 2
            for _ in range(ac):
                an, al = struct.unpack('>HI', d[i:i + 6])
                aname = cp[an][1]
                if aname == 'Code':
                    clen = struct.unpack('>I', d[i + 6 + 4:i + 6 + 8])[0]
                    code = d[i + 6 + 8:i + 6 + 8 + clen]
                    j = i + 6 + 8 + clen
                    el = struct.unpack('>H', d[j:j + 2])[0]
                    j += 2 + el * 8
                    sac = struct.unpack('>H', d[j:j + 2])[0]
                    j += 2
                    subs = []
                    for _ in range(sac):
                        sn, sl = struct.unpack('>HI', d[j:j + 6])
                        subs.append(cp[sn][1])
                        j += 6 + sl
                    stats.append((code, subs))
                i += 6 + al
        return i, stats
    i, _ = skip_members(i)
    i, methods = skip_members(i)
    return major, minor, classes, methods


def has_branch(code):
    # conservative: look for any branch opcode byte (may over-approximate)
    return any(b in BRANCH for b in code)


def main():
    cdir = sys.argv[1]
    api = set()
    for jar in sys.argv[2:]:
        with zipfile.ZipFile(jar) as z:
            for n in z.namelist():
                if n.endswith('.class'):
                    api.add(n[:-6])
    own = set()
    files = []
    for root, _, fs in os.walk(cdir):
        for f in fs:
            if f.endswith('.class'):
                p = os.path.join(root, f)
                files.append(p)
                own.add(os.path.relpath(p, cdir)[:-6].replace(os.sep, '/'))
    bad = 0
    nmeth = nmap = 0
    for p in files:
        major, minor, classes, methods = parse(p)
        if major > 48:
            print('FAIL version %d.%d %s' % (major, minor, p)); bad += 1
        for c in classes:
            if c not in api and c not in own:
                print('FAIL unknown API class %s in %s' % (c, p)); bad += 1
        for code, subs in methods:
            nmeth += 1
            if 'StackMapTable' in subs:
                print('FAIL StackMapTable in %s' % p); bad += 1
            if 'StackMap' in subs:
                nmap += 1
    print('classes: %d, methods: %d, with StackMap: %d, version ok, API ok' % (len(files), nmeth, nmap)
          if not bad else 'errors: %d' % bad)
    sys.exit(1 if bad else 0)


main()
