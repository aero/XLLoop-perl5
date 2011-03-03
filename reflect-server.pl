#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use XLLoop;

{
    package MyFuncs;
    use Data::Dump;
    use List::Util qw/sum/;
    use namespace::clean;

    # MyFuncs.somefunc(1) will send arguments as [1]
    # MyFuncs.somefunc(1,2) will send arguments as [1,2]
    # IF you send a range of cells
    # MyFuncs.somefunc(B1) will send arguments as [B1]
    # MyFuncs.somefunc(B1:D1) will send arguments as [[[B1,C1,D1]]]
    # MyFuncs.somefunc(B1:D3) will send arguments as [[[B1,C1,D1], [B2,C2,D2], [B3,C3,D3]]]
    sub sum_two {
        my ($a, $b) = @{+shift};
        return $a + $b;
    }
    sub sum_all {
        return sum(@{+shift});
    } 
    sub array {
        return [0..10];
    }
    sub matrix {
        return [[1,2.1],['hello',4]];
    }
    sub dump {
        say "dumping:";
        dd @_;
    }
}

{
    package TestFunc;
    use namespace::clean;

    sub div_two {
        my ($a, $b) = @{+shift};
        return $a / $b;
    }
}


my $h = ReflectionHandler->new;
$h->addMethods('MyFuncs.', 'MyFuncs'); # addMethods(prefix, package)
$h->addMethods('TestFunc.', 'TestFunc');
my $f = XLLoopServer->new( handler => $h );
$f->start;
