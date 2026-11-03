#pragma once
#include <memory>

struct Edge;

struct CommandRunner
{
    virtual ~CommandRunner() {}
    virtual bool StartCommand( Edge* edge ) = 0;
    virtual bool CanRunMore() const = 0;
};

struct Shape
{
    virtual ~Shape() {}
    virtual int area() const { return 0; }
};

struct Square : Shape
{
    int area() const override { return 4; }
};

struct SoloBase
{
    virtual ~SoloBase() {}
    virtual int soloRun( int n ) = 0;
};

struct Hollow
{
    virtual ~Hollow() {}
    virtual int hollowRun() = 0;
};

struct Builder
{
    std::unique_ptr<CommandRunner> command_runner_;
    bool startEdge( Edge* e );
};
