use warnings;
use strict;

package RT::View::RuleBuilder;
use Jifty::View::Declare -base;
use JSON;

sub _type_as_string {
    my ($type) = @_;
    return $type ? $type->name : undef;
}

sub _function_as_hash {
    my ($func) = @_;
    return { return_type => _type_as_string($func->return_type),
             parameters => [ map { { name => $_->name, type => _type_as_string($_->type) } } @{ $func->parameters || [] } ] };
}

template 'index.html' => page {
    title => "rule",
} content {
    my $l = $RT::Lorzy::LCORE;
    my $functions = $l->env->all_functions;
    my $data = { map { $_ => _function_as_hash($functions->{$_}) } keys %$functions };
    pre { to_json($data) };

    h1 { "Rule Builder"};
    # given transaction :: RT::Model::Transaction
    #       ticket :: RT::Model::Ticket
    # expect Bool
	div { { id is 'expression-filter'};
    input { { id is 'type-filter-type', type is 'text' } };
    input { { id is 'type-filter', type is 'button', value is 'filter' } };
    input { { id is 'type-unfilter', type is 'button', value is 'unfilter' } };
	}
    div { { id is 'expressionbuilder' } };
    input { { id is 'add-expression', type is 'button', value is 'Add Expression' } };
    outs_raw('<script type="text/javascript">
jQuery(function() {
    var rb = new RuleBuilder("#expressionbuilder");
    jQuery("#type-filter").click(function(e) { rb.filter_return_type(jQuery("#type-filter-type").val())});
    jQuery("#type-unfilter").click(function(e) { rb.unfilter_return_type()});
    jQuery("#add-expression").click(function(e) { rb.add_expression()});
});
</script>
');
    
#    show('list_functions');

};

template 'list_functions' => sub {
    my $l = $RT::Lorzy::LCORE;
    my $env = $l->env;
    my $functions;
    while ($env) {
        for (keys %{$env->symbols}) {
            if ($env->symbols->{$_}->does('LCore::Function')) {
                $functions->{$_} ||= $env->symbols->{$_};
            }
        }
        $env = $env->parent;
    }
    ul {
        for (keys %$functions) {
            next unless $functions->{$_}->return_type && $functions->{$_}->return_type eq 'Bool';
            li { $_ };
        }
    }
};

1;
