#pragma once

// gitcmd.h — THE one spelling of how ripwire starts a git child.
//
// Every git command this tool runs begins with gitCmd(), so the git-config trust boundary (githarden.h) is a
// property of the command line rather than of anything a caller has to detect first. The prefix is three
// policy options, applied to every invocation:
//
//   --no-optional-locks       ripwire's git calls are read-only. Without this, a `git status` that refreshes
//                             stat data opportunistically REWRITES the index — and with the monitor disabled
//                             that rewrite drops the index's fsmonitor extension, so the user's next status
//                             pays a full re-sync (measured, git 2.50.1). With it, the index is never written
//                             and ripwire never contends for index.lock with the user's own git.
//   -c core.fsmonitor=false   the command-line form governs the directory whatever config file would
//                             otherwise apply, and git passes it on to any git it spawns. The builtin daemon
//                             is not consulted by ripwire's own few calls either — their cost is a stat pass
//                             of the same order as the crawl ripwire already makes.
//   -c log.showSignature=false  signature display stays off whatever the repository's config says, so `git log`
//                             starts no signature program. ripwire's log formats never ask for a signature (and
//                             its parsers would misread the extra lines), so the pin changes no answer.
//                             Version-safe: a git that predates the key ignores it.
//
// FILTER DRIVERS. ripwire neutralises repository-configured filter and diff programs for its own git children.
// A repository's config may name `filter.<name>.clean/smudge/process` programs for git to use while it reads
// working-tree files. The driver NAME is chosen by the repository, so there is no single key to pin. githarden.h asks
// git, once per root, which filter drivers the repository-local config (local + worktree scope, includes
// followed) defines and registers them here; every later gitCmd() then carries
//     -c 'filter.<name>.clean=' -c 'filter.<name>.smudge=' -c 'filter.<name>.process=' -c 'filter.<name>.required=false'
// for each of them. An empty command is git's own "no filter" (convert.c), so the file is read as stored. A
// name that `-c` cannot spell (empty, or holding '=', which `-c` splits on) is not pinned: the process is
// FAIL-CLOSED instead — every later child carries kGitRefusedOption, an option no git accepts, so no git
// child runs at all rather than one run with a program the pins could not reach (githarden.h discloses it).
//
// DIFF PROGRAMS are pinned at the call site, because they are subcommand options, not global ones: every
// executed `diff`, `log`, `show` and `blame` carries `--no-ext-diff --no-textconv` (no diff.external,
// diff.<driver>.command or diff.<driver>.textconv program), and every `status` and `diff` carries
// `--ignore-submodules=dirty`, so git never starts a second git inside a submodule's OWN repository, whose
// config the per-root filter pins above do not cover. test/gitchildoptscheck.sh observes all of it from the
// child through a PATH shim.
//
// The ONE git command that must not carry the prefix is githarden's `git config --get core.fsmonitor` probe:
// a command-line value would BE the answer it reads back. A config read refreshes no index and runs no hook.
// Strings that merely SHOW a git command to the user (a `next=` hint, a printed shell snippet) are not
// invocations and keep their plain spelling.
//
// NEVER DOWNLOAD. On a partial clone (a promisor remote, `--filter=blob:none`), any git read of a missing object fetches
// it from the network, one batch at a time, without asking: a read-only `git log` grew a ClickHouse .git from 15 to 33 GB.
// denyGitLazyFetch() below is the policy, set once in the environment at the top of main() so every git child (and every
// git that child starts) inherits it, on any shell. Two layers, because the common distro gits predate the first:
//   GIT_NO_LAZY_FETCH=1             git 2.45 and later: git does not try. (An option, `git --no-lazy-fetch`, arrived in
//                                   2.44, and an older git REFUSES it with exit 129, so it cannot ride in this prefix.)
//   GIT_ALLOW_PROTOCOL=<no such>    git 2.12 and later: the fetch child git starts is refused at the transport, so the
//                                   download fails even when git tries. Beats any protocol.* config. Ignored by 2.11-.
// A read that needs a missing object then FAILS, exactly as a corrupt object does, and takes that verb's existing
// git-failed path. The one command of ours that means to use the network, resolveRemoteRoot's `clone`, lifts the second
// layer around itself (GitNetworkForClone). test/lazyfetchcheck.sh.
//
// Gated by test/githardencheck.sh: behavioural arms run the git-backed verbs through several root shapes and
// the MCP and --plan-lint entry points and assert a hook-form core.fsmonitor stays unfired; a PATH shim arm
// asserts every git child carries the prefix; a structural arm refuses an executed git command spelled
// outside gitCmd(). test/gitchildoptscheck.sh gates the filter pins and the diff-program options.

#include "infra/os.h"        // rw::os::setenv — denyGitLazyFetch, every child's no-download environment
#include "infra/shquote.h"   // rw::shSingleQuote — a driver name is the repository's text, quoted for the shell

#include <algorithm>
#include <cstdlib>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::string_view kGitCmdPrefix = "git --no-optional-locks -c core.fsmonitor=false -c log.showSignature=false";

// An option no git version accepts: git exits 129 before it reads a config file or a working tree. Carried by
// every child once a repository names a filter driver the -c pins cannot spell (see FILTER DRIVERS above).
inline constexpr std::string_view kGitRefusedOption = "--ripwire-refused-unpinnable-filter-driver";

// A protocol name no transport has: an allow-list of only this allows nothing.
inline constexpr const char* kGitNoFetchProtocols = "ripwire-no-network";

// The protocols the caller's environment allowed before denyGitLazyFetch replaced them; empty when it set none.
inline std::string& callerGitAllowProtocol()
{
    static std::string saved;
    return saved;
}

// NEVER DOWNLOAD (the header comment). Call ONCE, first thing in main(), before any thread (setenv is not thread-safe).
inline void denyGitLazyFetch()
{
    if( const char* caller = std::getenv( "GIT_ALLOW_PROTOCOL" ); caller != nullptr )
    {
        callerGitAllowProtocol() = caller;
    }
    os::setenv( "GIT_NO_LAZY_FETCH", "1", 1 );
    os::setenv( "GIT_ALLOW_PROTOCOL", kGitNoFetchProtocols, 1 );
}

// The scope of the one git command that means to use the network: a root the user named as a URL. The allow-list is what
// the caller's environment said, else git's ordinary transports (never ext::, which the clone also pins off). Single
// threaded: the clone runs before any walk starts.
class GitNetworkForClone
{
public:
    GitNetworkForClone()
    {
        const std::string& caller = callerGitAllowProtocol();
        os::setenv( "GIT_ALLOW_PROTOCOL", caller.empty() ? "https:http:ssh:git:file" : caller.c_str(), 1 );
    }
    ~GitNetworkForClone() { os::setenv( "GIT_ALLOW_PROTOCOL", kGitNoFetchProtocols, 1 ); }
    GitNetworkForClone( const GitNetworkForClone& )            = delete;
    GitNetworkForClone& operator=( const GitNetworkForClone& ) = delete;
};

namespace gitcmddetail
{
// The registered pins. Written by githarden (at startup, and by an MCP/LSP server when a request names a root
// it has not probed) and read by every gitCmd() call, possibly from a worker thread — hence the mutex. Append-only.
struct DriverPins
{
    std::mutex               lock;
    std::vector<std::string> names;      // every filter driver name pinned so far, in registration order
    std::string              options;    // the -c options (and the refusal, once set), each with its leading space
    bool                     refused = false;
};

inline DriverPins& driverPins()
{
    static DriverPins pins;
    return pins;
}
}   // namespace gitcmddetail

// What one registration did: how many names were new, and whether any of them could not be pinned (then every
// later child carries kGitRefusedOption).
struct DriverPinResult
{
    std::size_t added      = 0;
    bool        unpinnable = false;
};

// Register filter driver names. A name already pinned is skipped, so the options grow once per distinct name
// however many roots name it. `-c` takes `key=value` and splits at the FIRST '=', so a name holding '=' cannot be
// spelled; an empty name is not a subsection git can be told about either. Newline and NUL never reach here (git
// config cannot hold them in a subsection name).
inline DriverPinResult pinGitFilterDrivers( const std::vector<std::string>& names )
{
    gitcmddetail::DriverPins&         pins = gitcmddetail::driverPins();
    const std::lock_guard<std::mutex> guard( pins.lock );
    DriverPinResult                   result;
    for( const std::string& name : names )
    {
        if( std::find( pins.names.begin(), pins.names.end(), name ) != pins.names.end() )
        {
            continue;
        }
        pins.names.push_back( name );
        ++result.added;
        if( name.empty() || name.contains( '=' ) )
        {
            result.unpinnable = true;
            if( !pins.refused )
            {
                pins.refused = true;
                pins.options += ' ';
                pins.options += kGitRefusedOption;
            }
            continue;
        }
        for( std::string_view key : { ".clean=", ".smudge=", ".process=", ".required=false" } )
        {
            pins.options += " -c ";
            pins.options += shSingleQuote( "filter." + name + std::string( key ) );
        }
    }
    return result;
}

// `rest` is everything after the program name and the policy options, starting with its own leading space
// (" -c core.quotepath=false -C "), exactly as the call site spelled it after "git" before this header existed.
inline std::string gitCmd( std::string_view rest )
{
    gitcmddetail::DriverPins&   pins = gitcmddetail::driverPins();
    const std::lock_guard<std::mutex> guard( pins.lock );
    std::string cmd;
    cmd.reserve( kGitCmdPrefix.size() + pins.options.size() + rest.size() );
    cmd += kGitCmdPrefix;
    cmd += pins.options;
    cmd += rest;
    return cmd;
}

}   // namespace rw
