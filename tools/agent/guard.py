#!/usr/bin/env python3
"""Claude Code hook (before every shell command): stops the ways around the pull request rules.

Reads the hook's JSON on stdin. Exit 2 blocks the command and shows the message to the agent.
It looks at each command in the line on its own, so words inside a commit message, a grep or a heredoc do not count.
This is a seat belt, not a wall: branch protection on GitHub is the wall. Tests: tools/agent/test_agent.py
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

MERGE = 'merge with tools/agent/merge_pr.sh <pr>, or leave it for the owner.'
MAIN = 'nothing is pushed to main; open a pull request.'
HOOK = 'no going around the pre-push hook.'
LABEL = 'only the owner takes off needs-human or one-way-door.'
OUT = 'only the owner opens main, by running tools/agent/allow_main.sh in their own terminal. Ask them.'
ALLOW_FILE = 'factory-allow-main'
SEPARATORS = {';', '&&', '||', '|', '&', '(', ')', '|&', ';;'}
# Words that can stand in front of a command without changing what it is.
PREFIXES = {'command', 'env', 'sudo', 'time', 'nohup', 'exec', 'builtin', 'if', 'then', 'else', 'elif', 'do', 'while',
            'until', '{', '}', '!', 'fi', 'done'}
# Commands that run another command given after their own arguments.
RUNNERS = {'timeout', 'xargs', 'nice', 'env', 'sudo', 'caffeinate', 'watch'}
SHELLS = {'sh', 'bash', 'zsh', 'dash'}
GIT_VALUE_FLAGS = {'-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path'}
GH_VALUE_FLAGS = {'-R', '--repo'}
API_WRITE_TO = re.compile(r'pulls/\d+/merge|/merges$|git/refs/heads/main|merge-upstream', re.I)
API_MUTATION = re.compile(r'mergePullRequest|enablePullRequestAutoMerge|updateRef', re.I)
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
PROTECTED_LABELS = ('needs-human', 'one-way-door')


def without_heredocs(text):
    """The command line with the text of every heredoc taken out: that text is data, not commands."""
    lines, out, i = text.split('\n'), [], 0
    while i < len(lines):
        out.append(lines[i])
        for _, tag in HEREDOC.findall(lines[i]):
            i += 1
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
        i += 1
    return '\n'.join(out)


def commands(line):
    """The simple commands in a shell line, each as a list of words."""
    line = without_heredocs(line).replace('\\\n', ' ').replace('`', ' ; ')
    # A ';' on its own line after each line: a '#' comment eats to the end of its line and no further.
    lexer = shlex.shlex(line.replace('\n', '\n;\n'), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    out, now = [], []
    for word in lexer:                      # raises ValueError on an open quote
        if word in SEPARATORS:
            out.append(now)
            now = []
        else:
            now.append(word)
    out.append(now)
    return [c for c in (without_redirects(c) for c in out) if c]


def without_redirects(words):
    """A command's words with '2>&1', '> file', '< file' taken out: they are not arguments."""
    out, skip = [], False
    for word in words:
        if skip:
            skip = False
        elif word and set(word) <= set('<>&') and ('<' in word or '>' in word):
            if out and out[-1].isdigit():
                out.pop()                   # the 2 of 2>&1
            skip = True                     # and what it points at
        else:
            out.append(word)
    return out


def on_main(cwd):
    try:
        r = subprocess.run(['git', 'branch', '--show-current'], cwd=cwd or None, capture_output=True, text=True, timeout=5)
        return r.stdout.strip() == 'main'
    except Exception:
        return False


def main_is_open(cwd):
    """True while the owner's out is open: tools/agent/allow_main.sh wrote a time that has not passed."""
    try:
        r = subprocess.run(['git', 'rev-parse', '--git-common-dir'], cwd=cwd or None, capture_output=True, text=True, timeout=5)
        path = os.path.join(cwd or '', r.stdout.strip(), ALLOW_FILE)
        with open(path) as f:
            return r.returncode == 0 and time.time() < int(f.read().strip())
    except Exception:
        return False


def check_git(args, cwd, state):
    why = check_git_rules(args, cwd, state)
    return None if why == MAIN and main_is_open(cwd) else why


def check_git_rules(args, cwd, state):
    sub, i, pre = None, 0, args
    while i < len(args):
        a = args[i]
        if a == '-C' and i + 1 < len(args):
            cwd = os.path.join(cwd or '', args[i + 1])
        if a in GIT_VALUE_FLAGS:
            i += 2
        elif a.startswith('-'):
            i += 1
        else:
            sub, pre, args = a, args[:i], args[i + 1:]
            break
    if any('core.hookspath' in a.lower() for a in pre):
        return HOOK
    if sub == 'config' and any(a.lower() == 'core.hookspath' for a in args):
        values = [a for a in args if not a.startswith('-') and a.lower() != 'core.hookspath']
        reading = (not values or '--get' in args or '--get-all' in args) and '--unset' not in args and '--unset-all' not in args
        if not reading and values != ['.githooks']:
            return HOOK
    if sub in ('checkout', 'switch') and args[-1:] == ['main'] and not any(a in ('-b', '-B', '-c', '-C', '--') for a in args):
        state['main'] = True
    if sub != 'push':
        return None
    if '--no-verify' in args:
        return HOOK
    if any(a in ('--all', '--mirror', '--branches') for a in args):
        return MAIN
    names = [a for a in args if not a.startswith('-')]
    refs = [r for r in names[1:] if r != ':']          # names[0] is the remote
    for ref in refs:
        to = ref.lstrip('+').split(':')[-1]
        if to in ('main', 'heads/main', 'refs/heads/main'):
            return MAIN
    if (not refs or 'HEAD' in refs) and (state.get('main') or on_main(cwd)):
        return MAIN
    return None


def flag_value(args, i, long_name):
    """The value of a flag at args[i], written '--flag value' or '--flag=value'; '' when args[i] is not that flag."""
    if args[i] == long_name and i + 1 < len(args):
        return args[i + 1]
    if args[i].startswith(long_name + '='):
        return args[i].split('=', 1)[1]
    return ''


def check_gh(args):
    words, i = [], 0
    while i < len(args):
        if args[i] in GH_VALUE_FLAGS:
            i += 2
        elif args[i].startswith('-'):
            i += 1
        else:
            words.append(args[i])
            i += 1
    if words[:2] == ['pr', 'merge']:
        return MERGE
    if words[:2] in (['pr', 'edit'], ['issue', 'edit']):
        for i in range(len(args)):
            if any(label in flag_value(args, i, '--remove-label').split(',') for label in PROTECTED_LABELS):
                return LABEL
    if words[:1] == ['api']:
        if any(API_MUTATION.search(a) for a in args):
            return MERGE
        method = ''
        for i, a in enumerate(args):
            method = (flag_value(args, i, '--method') or flag_value(args, i, '-X') or (a[2:] if re.match(r'^-X\w', a) else '') or method).upper()
        fields = any(a in ('-f', '-F', '--field', '--raw-field', '--input') for a in args)
        writes = method in ('PUT', 'POST', 'PATCH', 'DELETE') or (fields and method != 'GET')
        if writes and any(API_WRITE_TO.search(a) for a in args):
            return MERGE
    return None


def check(line, cwd=None, depth=0, state=None):
    """Why this command line is blocked, or None when it is fine."""
    state = {} if state is None else state
    if ALLOW_FILE in line:                  # anywhere in the line: a redirect can write it
        return OUT
    try:
        cmds = commands(line)
    except ValueError:
        return 'could not read this command (open quote?). Write it more simply.'
    for words in cmds:
        while words:
            if re.match(r'^GIT_CONFIG_(COUNT|KEY|VALUE|PARAMETERS)', words[0]):
                return HOOK
            if words[0] in PREFIXES or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', words[0]):
                words = words[1:]
            else:
                break
        if not words:
            continue
        if any(os.path.basename(w) == 'allow_main.sh' for w in words):
            return OUT
        name = os.path.basename(words[0])
        if name in RUNNERS:                 # timeout 60 git push ...: look at the command it runs
            known = ('git', 'gh', 'curl', 'eval') + tuple(SHELLS)
            inner = [i for i, w in enumerate(words) if os.path.basename(w) in known]
            if not inner:
                continue
            words = words[inner[0]:]
            name = os.path.basename(words[0])
        args = words[1:]
        why = None
        if name == 'git':
            why = check_git(args, cwd, state)
        elif name == 'gh':
            why = check_gh(args)
        elif name == 'curl' and any(API_WRITE_TO.search(a) or API_MUTATION.search(a) for a in args):
            why = MERGE
        elif depth < 3 and name == 'eval':
            why = check(' '.join(args), cwd, depth + 1, state)
        elif depth < 3 and name in SHELLS:
            flag = [i for i, a in enumerate(args) if re.match(r'^-[A-Za-z]*c$', a)]
            if flag and flag[0] + 1 < len(args):
                why = check(args[flag[0] + 1], cwd, depth + 1, state)
        if why:
            return why
    return None


def main():
    try:
        hook = json.load(sys.stdin)
        line = hook.get('tool_input', {}).get('command', '')
        cwd = hook.get('cwd')
    except Exception:
        print('Blocked: the guard could not read the hook input.', file=sys.stderr)
        return 2
    why = check(line, cwd)
    if why:
        print('Blocked: %s See docs/agents/workflow.md.' % why, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
