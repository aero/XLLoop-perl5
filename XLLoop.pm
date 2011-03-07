package XLLoop;

use 5.010;
use strict;
use warnings;

#  Defines the XLoper types
my $XL_TYPE_NUM     = 1;
my $XL_TYPE_STR     = 2;
my $XL_TYPE_BOOL    = 3;
my $XL_TYPE_ERR     = 4;
my $XL_TYPE_MULTI   = 5;
my $XL_TYPE_MISSING = 6;
my $XL_TYPE_NIL     = 7;
my $XL_TYPE_INT     = 8;
my $XL_TYPE_SREF    = 9;

# Defines XLError types
my $XL_ERROR_NULL  =  0;
my $XL_ERROR_DIV0  =  7;
my $XL_ERROR_VALUE = 15;
my $XL_ERROR_REF   = 23;
my $XL_ERROR_NAME  = 29;
my $XL_ERROR_NUM   = 36;
my $XL_ERROR_NA    = 42;

{
    package XLError;
    use Any::Moose;

    has err => (is => 'ro', isa => 'Int');
}

{
    package XLSRef;
    use Any::Moose;

    has col_first => (is => 'ro', isa => 'Int');
    has col_last  => (is => 'ro', isa => 'Int');
    has rw_first  => (is => 'ro', isa => 'Int');
    has rw_last   => (is => 'ro', isa => 'Int');
}

{
    package XLCodec;
    use autobox::universal qw/type/;
    use Carp;

    sub decode {
        my ($fh) = @_;

        my $type;
        sysread $fh, $type, 1;
        given (ord $type) {
            when ($XL_TYPE_NUM) {
                my $data;
                sysread $fh, $data, 8;
                return unpack('d>', $data);
            }
            when ($XL_TYPE_STR) {
                my $len;
                sysread $fh, $len, 1;
                $len = ord $len;
                my $data;
                sysread $fh, $data, $len;
                return $data;
            }
            when ($XL_TYPE_BOOL) {
                my $data;
                sysread $fh, $data, 1;
                my $bool = ord $data;
                return $bool == 0 ? 0 : 1;
            }
            when ($XL_TYPE_ERR) {
                return XLError->new(err => XLCodec::decodeInt($fh));
            }
            when ($XL_TYPE_MULTI) {
                my $rows = XLCodec::decodeInt($fh);
                my $cols = XLCodec::decodeInt($fh);
                return [] if $cols == 0 || $rows == 0;
                my $a = [];
                if ($cols > 1) {
                    foreach (0..$rows-1) {
                        my $aa;
                        foreach (0..$cols-1) {
                            push @$aa, XLCodec::decode($fh);
                        }
                        push @$a, $aa;
                    }
                } else {
                    foreach (0..$rows-1) {
                        push @$a,  XLCodec::decode($fh);
                    }
                }
                return $a;
            }
            when ($XL_TYPE_MISSING) { return undef; }
            when ($XL_TYPE_NIL) { return undef; }
            when ($XL_TYPE_INT) {
                return XLCodec::decodeInt($fh);
            }
            when ($XL_TYPE_SREF) {
                return XLSRef->new(
                    col_first => XLCodec::decodeInt($fh), col_last  => XLCodec::decodeInt($fh),
                    rw_first  => XLCodec::decodeInt($fh), rw_last   => XLCodec::decodeInt($fh)
                );
            }
            default {
                croak "Invalid XLoper type encountered";
            }
        } # end of given 
    }

    sub decodeInt {
        my ($fh) = @_;
        my @bytes = map { my $byte; sysread $fh, $byte, 1; ord $byte } 0..3;
        return $bytes[0] << 24 | $bytes[1] << 16 | $bytes[2] << 8 | $bytes[3];
    }

    sub encode {
        my ($value, $fh) = @_;

        if (type($value) eq 'STRING') {
            syswrite $fh, pack('C', $XL_TYPE_STR);
            syswrite $fh, pack('C', length($value));
            syswrite $fh, $value; 
        } elsif (type($value) eq 'FLOAT') {
            syswrite $fh, pack('C', $XL_TYPE_NUM);
            syswrite $fh, pack('d>', $value);
        } elsif (! defined $value) {
            syswrite $fh, pack('C', $XL_TYPE_NIL);
        } elsif (ref($value) eq 'XLError') {
            syswrite $fh, pack('C', $XL_TYPE_ERR);
            syswrite $fh, pack('i>', $value->err);
        } elsif (ref($value) eq 'XLSRef') {
            syswrite $fh, pack('C', $XL_TYPE_SREF);
            syswrite $fh, pack('i>', $value->col_first);
            syswrite $fh, pack('i>', $value->col_last);
            syswrite $fh, pack('i>', $value->rw_first);
            syswrite $fh, pack('i>', $value->rw_last);
        } elsif (type($value) eq 'INTEGER') {
            syswrite $fh, pack('C', $XL_TYPE_NUM);
            syswrite $fh, pack('d>', $value*1.0);
        } elsif (ref($value) eq 'HASH') {
            my $a = [];
            push @$a, [$_, $value->{$_}] for keys %$value;
            XLCodec::encode($a, $fh);
        } elsif (ref($value) eq 'ARRAY') {
            syswrite $fh, pack('C', $XL_TYPE_MULTI);
            my $rows = scalar @$value;
            syswrite $fh, pack('i>', $rows);
            if ($rows == 0) {
                syswrite $fh, pack('i>', 0);
            } else {
                my $v = $value->[0];
                if (ref($v) eq 'ARRAY') {
                    my $cols = scalar @$v;
                    syswrite $fh, pack('i>', $cols);
                    foreach my $i (0..$rows-1) {
                        my $v = $value->[$i];
                        if (ref($v) eq 'ARRAY') {
                            my $l = scalar @$v;
                            if ($l < $cols) {
                                foreach my $j (0..$l-1) { XLCodec::encode($v->[$j], $fh) }
                                foreach my $j ($l..$cols-1) { XLCodec::encode(undef, $fh) }
                            } else {
                                foreach my $j (0..$cols-1) { XLCodec::encode($v->[$j], $fh) }
                            }
                        } else {
                            XLCodec::encode($v, $fh);
                            foreach my $j (1..$cols-1) { XLCodec::encode(undef, $fh) }
                        }
                    }
                } else {
                    syswrite $fh, pack('i>', 1);
                    foreach my $i (0..$rows-1) {
                        XLCodec::encode($value->[$i], $fh);
                    }
                }
            }
        } else {
            XLCodec::encode("$value", $fh);
        }
    }
}

{
    package FunctionContext;
    use Any::Moose;

    has caller     => (is => 'ro', isa => 'Str');
    has sheet_name => (is => 'ro', isa => 'Str');
}

{
    package FunctionInformation;
    use Any::Moose; 

    has name        => (is => 'ro', isa => 'Str', required => 1);
    has help        => (is => 'ro', isa => 'Str');
    has category    => (is => 'rw', isa => 'Str');
    has shortcut    => (is => 'rw', isa => 'Str');
    has topic       => (is => 'rw', isa => 'Str');
    has _args       => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
    has _argsHelps  => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });
    has _isVolatile => (is => 'rw', isa => 'Bool', default => 0); 

    sub addArg {
        my ($self, $name, $help) = @_;
        push @{$self->_args}, $name;
        push @{$self->_argsHelps}, $help;
    }

    sub getinfo {
        my ($self) = @_;

        my $h = {};
        $h->{functionName} = $self->name;
        $h->{functionHelp} = $self->help if $self->help;
        $h->{category} = $self->category if $self->category;
        $h->{shortcutText} = $self->shortcut if $self->shortcut;
        $h->{helpTopic} = $self->topic if $self->topic;
        $h->{isVolatile} = $self->_isVolatile if $self->_isVolatile;
        if ( @{$self->_args} > 0 ) {
            $h->{argumentText} = join ',', @{$self->_args};
            $h->{argumentHelp} = $self->_argsHelps;
        }

        return $h;
    }

}

{
    package ReflectionHandler;
    use Any::Moose;

    has _methods => (is => 'rw', isa => 'HashRef', default => sub { +{} });

    sub addMethods {
        my $self = shift;
        my $namespace = shift // '';
        my $package = shift;

        no strict;
        my @methods = grep { *{$package."::$_"}{CODE}  } keys %{$package.'::'};
        foreach my $m (@methods) {
            ${$self->_methods}{$namespace.$m} = *{$package."::$m"}{CODE};
        }
    }

    sub invoke {
        my ($self, $context, $name, $args) = @_;

        my $m = $self->_methods->{$name};
        while ( @$args>0  && !defined $args->[-1]) { pop @$args }  # removing trailing undef
        if ( ! $m ) {
            if ($name eq 'org.boris.xlloop.GetFunctions') {
                my $fi = [];
                foreach my $m (keys %{$self->_methods}) {
                    push @$fi, [FunctionInformation->new( name=>$m )->getinfo];
                }
                return $fi;
            } else {
                return '#Unknown Function';
            }
        } else {
            return $m->($args);
        } 
    }
}

{
    package XLLoopServer;
    use Any::Moose;
    use threads;
    use IO::Socket::INET;
    use Carp;
    use Try::Tiny;

    has _server => (is => 'rw', isa => 'IO::Socket::INET');

    has handler => (is => 'ro', isa => 'Object', required => 1);
    has port    => (is => 'ro', isa => 'Int', default => 5454);

    sub start {
        my ($self) = @_;
        $self->_server(IO::Socket::INET->new(LocalPort => $self->port, ReuseAddr => 1, Listen => 10));
        while ( my $socket = $self->_server->accept ) {
            async(\&handle_connection, $socket, $self->handler)->detach;
        }

        sub handle_connection {
            my ($fh, $handler) = @_;
            while ($fh->connected) {
                try { 
                    my $context;
                    my $name = XLCodec::decode($fh);
                    if ("$name" =~ m/^\d+$/) {
                        my $version = $name;
                        if ($version == 20) {
                            my $extra_info = XLCodec::decode($fh);
                            if ( $extra_info ) {
                                my $caller = XLCodec::decode($fh);
                                my $sheet_name = XLCodec::decode($fh);
                                my $context = FunctionContext->new(caller => $caller, sheet_name => $sheet_name);
                            } 
                        } else {
                            croak "Unknown protocol version";
                        }
                        $name = XLCodec::decode($fh);
                    }
                    my $argc = XLCodec::decode($fh);
                    my $args = [];
                    foreach my $i (0..$argc-1) {
                        push @$args, XLCodec::decode($fh);
                    }
                    say "handler:".$name;
                    use Data::Dump;
                    say "args:";
                    dd $args;
                    my $res = $handler->invoke($context, $name, $args);
                    say "res:";
                    dd $res;
                    XLCodec::encode($res, $fh);
                } catch {
                    carp "Error. $_\n";
                    close $fh;
                }
            }
        }
    }

    sub stop {
        my ($self) = @_;
        $self->_server->shutdown;
    }
}

1;
