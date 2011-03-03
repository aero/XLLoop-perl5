#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use XLLoop;

{
    package TestHandler;
    use Any::Moose;

    has _functionInfo => (is => 'ro', isa => 'ArrayRef', default => \&_createFunctionInfo);

    sub invoke {
        my ($self, $context, $name, $args) = @_;
        given ($name) {
            when ('ArgsTest') {
                return $args;
            }
            when ('ReturnTest') {
                #return [1,1.2,'hello'];
                #return [[1,2],['hello',4.1]];
                return [0..100];
            }
            when ('MyTest') {
                my ($a, $b) = @{$args};
                return $a+$b;
            }
            when ('org.boris.xlloop.GetFunctions') {
                return $self->_functionInfo;
            }
            default {
                return "#Unknown function"; 
            }
        }
    }

    sub _createFunctionInfo {
        my $a = [];
        push @$a, FunctionInformation->new( name=>'ArgsTest', help=>'This is a args test')->getinfo;
        my $f1 = FunctionInformation->new( name=>'MyTest', help=>'This is a dummy test');
        $f1->addArg('anything', 'Test this one');
        $f1->addArg('else', 'Whatever you like');
        $f1->category('Testing');
        push @$a, $f1->getinfo;

        return $a;
    }
}

my $h = TestHandler->new;
my $f = XLLoopServer->new( handler => $h );
$f->start;
