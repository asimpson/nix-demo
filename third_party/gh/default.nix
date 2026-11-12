# gh (GitHub CLI) that cannot create issues, pull requests or commits.
#
# Patches are numbered and named by purpose:
#   001-deny-creating-issues-prs-and-commits.patch - Refuses, in the HTTP client
#     every gh command uses (`gh api` included), the REST requests and GraphQL
#     mutations that create issues, pull requests or commits
#   002-disable-token-output.patch - Refuses `gh auth token`,
#     `gh auth status --show-token` and `gh config get oauth_token`, which would
#     let curl or another tool write with gh's token
#   003-disable-git-credential-helper.patch - Refuses `gh auth git-credential`,
#     which would let `git push` create commits with gh's token
#   004-disable-extensions.patch - Refuses to run gh extensions, which talk to
#     GitHub with their own HTTP client
#
# Usage in overlay:
#   gh = import ../third_party/gh { inherit (prev) gh; };

{ gh }:

gh.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or []) ++ [
    ./001-deny-creating-issues-prs-and-commits.patch
    ./002-disable-token-output.patch
    ./003-disable-git-credential-helper.patch
    ./004-disable-extensions.patch
  ];
})
