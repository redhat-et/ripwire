#include "runner.h"

struct RealCommandRunner : CommandRunner
{
    bool StartCommand( Edge* edge ) override;
    bool CanRunMore() const override { return true; }
};

bool RealCommandRunner::StartCommand( Edge* edge )
{
    return edge != nullptr;
}

struct DryRunCommandRunner : CommandRunner
{
    bool StartCommand( Edge* edge ) override { return edge == nullptr; }
    bool CanRunMore() const override { return false; }
    bool StartCommand( Edge* edge, int extra ) { return extra > 0 && edge; }
};

struct OnlySolo : SoloBase
{
    int soloRun( int n ) override { return n + 1; }
};

struct Unrelated
{
    int hollowRun() { return 1; }
};

struct Unrelated2
{
    int hollowRun() { return 2; }
};
