# NixOS VM test: the patched gh must refuse to create issues, pull requests and
# commits, through its own commands and through `gh api`, while reads and other
# writes keep working. gh talks to a fake GitHub (fake-github.py) on
# api.github.localhost, which logs every request it receives, so each refusal
# is checked on the server side too. `stockGh` is nixpkgs' unpatched gh: it
# shows the same commands do reach the fake server, so the patch is what stops
# them.
{ pkgs, stockGh }:

pkgs.testers.runNixOSTest {
  name = "gh-no-writes";

  nodes.machine = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.gh pkgs.git ]; # gh pr create needs git
    networking.hosts."127.0.0.1" = [ "api.github.localhost" ];
    systemd.services.fake-github = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -I ${./fake-github.py} 80 /tmp/requests.jsonl";
    };
  };

  testScript = ''
    import json, shlex

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_open_port(80)

    assert machine.succeed("readlink -f $(command -v gh)").strip().startswith("${pkgs.gh}"), "VM is not using the patched gh"

    env = ("GH_HOST=github.localhost GH_TOKEN=fake-token GH_PROMPT_DISABLED=1 "
           "GH_NO_UPDATE_NOTIFIER=1 GH_CONFIG_DIR=/tmp/gh XDG_CACHE_HOME=/tmp/cache GH_DATA_DIR=/tmp/data NO_COLOR=1")
    stock = "${stockGh}/bin/gh"

    def requests(cmd, gh="gh", ok=False):
        """Run a gh command line and return the requests the fake server got."""
        machine.succeed("rm -rf /tmp/cache; : > /tmp/requests.jsonl")
        run = machine.succeed if ok else machine.fail
        out = run(f"{env} {gh} {cmd} 2>&1 </dev/null")
        reqs = [json.loads(l) for l in machine.succeed("cat /tmp/requests.jsonl").splitlines()]
        return out, [f"{r['method']} {r['path']} {r['body']}" for r in reqs]

    def refused(cmd, write):
        out, reqs = requests(cmd)
        assert "disabled and not allowed" in out, f"`gh {cmd}` was not refused: {out}"
        assert not [r for r in reqs if write in r], f"`gh {cmd}` reached the server: {reqs}"

    issue = "issue create -R owner/repo --title t --body b"
    pr = "pr create -R owner/repo --head feature --base main --title t --body b"
    merge = "pr merge 2 -R owner/repo --merge"

    with subtest("control: stock gh creates and merges against the fake server"):
        for cmd, write in [(issue, "createIssue"), (pr, "createPullRequest"), (merge, "mergePullRequest"),
                           ("api -X POST repos/owner/repo/git/commits -f message=m -f tree=t", "POST /repos/owner/repo/git/commits")]:
            _, reqs = requests(cmd, gh=stock, ok=True)
            assert [r for r in reqs if write in r], f"stock `gh {cmd}` did not send {write}: {reqs}"

    with subtest("gh commands that create issues, pull requests and commits are refused"):
        refused(issue, "createIssue")
        refused(pr, "createPullRequest")
        refused(merge, "mergePullRequest")

    with subtest("gh api REST routes are refused"):
        for method, path in [("POST", "repos/owner/repo/issues"), ("POST", "repositories/1/issues"),
                             ("POST", "repos/owner/repo/pulls"), ("POST", "repos/owner/repo/git/commits"),
                             ("PUT", "repos/owner/repo/contents/README.md"), ("DELETE", "repos/owner/repo/contents/README.md"),
                             ("PUT", "repos/owner/repo/pulls/2/merge"), ("POST", "repos/owner/repo/merges"),
                             ("POST", "repos/owner/repo/merge-upstream"), ("post", "repos/owner/repo//./issues")]:
            refused(f"api -X {method} {path} -f x=y", method.upper() + " /")

    with subtest("gh api graphql mutations are refused, however they are written"):
        for query, name in [('mutation { createIssue(input:{}) { clientMutationId } }', "createIssue"),
                            ('mutation { a: # comment\n createPullRequest(input:{}) { clientMutationId } }', "createPullRequest"),
                            ('mutation { ...F } fragment F on Mutation { createCommitOnBranch(input:{}) { clientMutationId } }', "createCommitOnBranch")]:
            refused("api graphql -f query=" + shlex.quote(query), name)
        machine.succeed("""printf '{"query":"mutation { \\\\u0063reateIssue(input:{}) { clientMutationId } }"}' > /tmp/escaped.json""")
        refused("api graphql --input /tmp/escaped.json", "reateIssue")
        machine.succeed("""printf '{"query":"mutation { mergePullRequest(input:{}) { clientMutationId } }","Query":"query { viewer { login } }"}' > /tmp/dup.json""")
        refused("api graphql --input /tmp/dup.json", "mergePullRequest")

    with subtest("gh does not hand its token to other tools"):
        for cmd in ["auth token", "auth status --show-token", "config get oauth_token -h github.localhost"]:
            out = machine.fail(f"{env} gh {cmd} 2>&1")
            assert "disabled and not allowed" in out and "fake-token" not in out, out
        out = machine.fail(f"printf 'protocol=https\\nhost=github.localhost\\n\\n' | {env} gh auth git-credential get 2>&1")
        assert "disabled and not allowed" in out and "fake-token" not in out, out

    with subtest("gh extensions do not run"):
        machine.succeed("mkdir -p /tmp/gh-hello && printf '#!/bin/sh\\necho hello\\n' > /tmp/gh-hello/gh-hello && chmod +x /tmp/gh-hello/gh-hello")
        machine.succeed(f"cd /tmp/gh-hello && {env} gh extension install .")
        for cmd in ["hello", "extension exec hello"]:
            out = machine.fail(f"{env} gh {cmd} 2>&1")
            assert "disabled and not allowed" in out and "hello\n" not in out, out

    with subtest("reads and other writes still work"):
        for cmd, sent in [("api repos/owner/repo/issues", "GET /repos/owner/repo/issues"),
                          ("api -X PATCH repos/owner/repo/issues/1 -f state=closed", "PATCH /repos/owner/repo/issues/1"),
                          ("api -X POST repos/owner/repo/issues/1/comments -f body=createIssue", "POST /repos/owner/repo/issues/1/comments"),
                          ("api graphql -f query='query { viewer { login } }'", "viewer"),
                          ("""api graphql -f query='mutation($b:String!){addComment(input:{subjectId:"I_1",body:$b}){clientMutationId}}' -f b=createIssue""", "addComment")]:
            _, reqs = requests(cmd, ok=True)
            assert [r for r in reqs if sent in r], f"`gh {cmd}` did not reach the server: {reqs}"
  '';
}
