# A stand-in for api.github.localhost, which gh talks to over plain HTTP when
# GH_HOST=github.localhost. It answers just enough for `gh issue create` and
# `gh pr create` to reach their final write, and appends every request it
# receives to the log file given as argv[2] so tests can see what got through.
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit

port, log_path = int(sys.argv[1]), sys.argv[2]

REPO = {
    "id": "R_1", "name": "repo", "nameWithOwner": "owner/repo",
    "owner": {"login": "owner"}, "url": "http://github.localhost/owner/repo",
    "isPrivate": False, "isFork": False, "parent": None,
    "hasIssuesEnabled": True, "viewerPermission": "WRITE",
    "defaultBranchRef": {"name": "main", "target": {"oid": "0" * 40}},
    "issueTemplates": [], "pullRequestTemplates": [],
    "pullRequests": {"nodes": []},
}
ISSUE = {"id": "I_1", "number": 1, "url": "http://github.localhost/owner/repo/issues/1"}
PR = {"id": "PR_1", "number": 2, "url": "http://github.localhost/owner/repo/pull/2"}
DATA = {
    "viewer": {"login": "tester", "id": "U_1"},
    "repository": REPO,
    "createIssue": {"issue": ISSUE},
    "createPullRequest": {"pullRequest": PR},
}


class Handler(BaseHTTPRequestHandler):
    def handle_one(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        path = urlsplit(self.path).path  # absolute URI when used as a proxy
        with open(log_path, "a") as f:
            f.write(json.dumps({"method": self.command, "path": path, "body": body}) + "\n")
        if path == "/graphql":
            payload = {"data": {k: v for k, v in DATA.items() if k in body}}
        elif path.endswith("/pulls") and self.command == "POST":
            payload = PR
        elif path.endswith("/issues") and self.command == "POST":
            payload = ISSUE
        else:
            payload = {"login": "tester", "sha": "1" * 40, "commit": {"sha": "1" * 40}}
        out = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.send_header("X-OAuth-Scopes", "repo")
        self.end_headers()
        self.wfile.write(out)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_one

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
