#!/usr/bin/env python3
"""Async JSON-RPC style backend for jedi.vim.

Reads one JSON object per line from stdin and writes one JSON object per
line to stdout. Designed to be driven by Vim's job_start / ch_evalexpr.
"""

import hashlib
import json
import sys
import traceback

import jedi


class _ScriptCache:
    """Keep one jedi.Script instance per (path, code) so internal caches warm up."""

    def __init__(self, server, maxsize=8):
        self._server = server
        self._maxsize = max(maxsize, 1)
        self._cache = {}          # key -> Script
        self._order = []          # LRU order, most recent at end

    def _key(self, code, path):
        path = path or ""
        return hashlib.sha256((path + "\n" + code).encode("utf-8")).hexdigest()

    def get(self, code, path):
        key = self._key(code, path)
        if key in self._cache:
            self._order.remove(key)
            self._order.append(key)
            return self._cache[key]

        script = self._server._create_script(code, path)
        self._cache[key] = script
        self._order.append(key)
        if len(self._order) > self._maxsize:
            oldest = self._order.pop(0)
            self._cache.pop(oldest, None)
        return script

    def clear(self):
        self._cache.clear()
        self._order.clear()


class JediServer:
    def __init__(self):
        self.env = None
        self._script_cache = _ScriptCache(self)

    def set_virtual_env(self, path):
        """Configure jedi to use a virtual environment."""
        if not path:
            self.env = None
        else:
            try:
                self.env = jedi.create_environment(path, safe=False)
            except Exception:
                self.env = None
                sys.stderr.write(traceback.format_exc())
        # Environment changed: cached Scripts are stale.
        self._script_cache.clear()

    def _create_script(self, code, path):
        kwargs = {"code": code}
        if path:
            kwargs["path"] = path
        if self.env is not None:
            kwargs["environment"] = self.env
        return jedi.Script(**kwargs)

    def _script(self, code, path):
        return self._script_cache.get(code, path)

    def handle(self, request):
        # Vim's JSON channel protocol wraps each message as [id, expr].
        if isinstance(request, list) and len(request) == 2:
            req_id, payload = request
            if isinstance(payload, dict):
                method = payload.get("method")
                params = payload.get("params", {})
            elif isinstance(payload, list) and len(payload) == 2:
                method, params = payload
            else:
                return [req_id, "invalid payload: %s" % payload]
        elif isinstance(request, dict):
            req_id = request.get("id")
            method = request.get("method")
            params = request.get("params", {})
        else:
            return [None, "invalid request: %s" % request]

        try:
            if method == "init":
                self.set_virtual_env(params.get("virtual_env"))
                env_desc = repr(self.env) if self.env is not None else None
                return [req_id, {"ok": True, "environment": env_desc}]

            if method == "complete":
                return [req_id, self._complete(params)]

            if method == "goto":
                return [req_id, self._goto(params)]

            if method == "get_doc":
                return [req_id, self._get_doc(params)]

            if method == "get_signature":
                return [req_id, self._get_signatures(params)]

            return [req_id, "unknown method: %s" % method]
        except Exception:
            return [req_id, traceback.format_exc()]

    def _complete(self, params):
        code = params.get("code", "")
        line = params.get("line", 1)
        column = params.get("column", 0)
        path = params.get("path")

        script = self._script(code, path)
        completions = script.complete(line, column)

        items = []
        for c in completions:
            item = {
                "word": c.name,
                "abbr": c.name_with_symbols,
                "menu": c.description,
                "info": c.docstring(),
                "kind": c.type,
            }
            items.append(item)
        return items

    def _goto(self, params):
        code = params.get("code", "")
        line = params.get("line", 1)
        column = params.get("column", 0)
        path = params.get("path")
        goto_type = params.get("goto_type", "definition")

        script = self._script(code, path)
        if goto_type == "assignment":
            results = script.goto(line, column, follow_imports=True)
        elif goto_type == "type":
            results = script.infer(line, column)
        else:
            results = script.goto(line, column, follow_imports=True)

        out = []
        for d in results:
            module_path = d.module_path
            if module_path is None:
                continue
            out.append({
                "path": str(module_path),
                "line": d.line or 1,
                "column": d.column or 0,
                "description": d.description,
            })
        return out

    def _get_doc(self, params):
        code = params.get("code", "")
        line = params.get("line", 1)
        column = params.get("column", 0)
        path = params.get("path")

        script = self._script(code, path)
        results = script.help(line, column)
        docs = [r.docstring() for r in results if r.docstring()]
        return {"doc": "\n\n".join(docs) if docs else ""}

    def _get_signatures(self, params):
        code = params.get("code", "")
        line = params.get("line", 1)
        column = params.get("column", 0)
        path = params.get("path")

        script = self._script(code, path)
        signatures = script.get_signatures(line, column)

        out = []
        for s in signatures:
            out.append({
                "name": s.name,
                "to_string": s.to_string(),
                "params": [p.to_string() for p in s.params],
                "index": s.index,
            })
        return out

    def run(self):
        # Ensure stdout is line buffered. This may fail when stdout is a
        # non-standard stream, so errors are swallowed.
        try:
            if hasattr(sys.stdout, "reconfigure"):
                sys.stdout.reconfigure(line_buffering=True)
        except Exception:
            pass

        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                request = json.loads(line)
            except json.JSONDecodeError as e:
                self._write({"error": "json decode: %s" % e})
                continue

            response = self.handle(request)
            self._write(response)

    def _write(self, obj):
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    server = JediServer()
    server.run()
