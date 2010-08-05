###########################################################################
# whatbot/Controller.pm
###########################################################################
# Handles incoming messages and where they go
###########################################################################
# the whatbot project - http://www.whatbot.org
###########################################################################

use MooseX::Declare;

class whatbot::Controller extends whatbot::Component {
    use whatbot::Message;
    use Class::Inspector;

    has 'command'            => ( is => 'rw', isa => 'HashRef' );
    has 'command_name'       => ( is => 'rw', isa => 'HashRef' );
    has 'command_short_name' => ( is => 'rw', isa => 'HashRef' );
    has 'skip_extensions'    => ( is => 'rw', isa => 'Int' );

    method BUILD ($) {
    	$self->build_command_map();
    }

    method build_command_map {
    	my %command;	    # Ordered list of commands
    	my %command_name;   # Maps command names to commands
    	my %command_short_name;
    	my $command_namespace = 'whatbot::Command';
    	my $root_dir = $INC{'whatbot/Controller.pm'};
    	$root_dir =~ s/Controller\.pm/Command/;
	
	    # Scan whatbot::Command directory for loadable plugins
    	opendir( COMMAND_DIR, $root_dir );
    	while ( my $name = readdir(COMMAND_DIR) ) {
    		next unless ( $name =~ /^[A-z0-9]+\.pm$/ );
		
    		my $command_path = $root_dir . '/' . $name;
    		$name =~ s/\.pm//;
    		my $class_name = 'whatbot::Command::' . $name;
    		eval "require $class_name";
    		if ($@) {
    			$self->log->error( $class_name . ' failed to load: ' . $@ );
    		} else {
    			unless ( $class_name->can('register') ) {
    				$self->log->error( $class_name . ' failed to load due to missing methods' );
    			} else {
    			    my @run_paths;
    			    my %end_paths;
    			    my $command_root = $class_name;
    			    $command_root =~ s/$command_namespace\:\://;
    			    $command_root = lc($command_root);
			    
    				# Instantiate
    				my $config;
    				if (defined $self->config->commands->{lc($name)}) {
    					$config = $self->config->commands->{lc($name)};
    				}
    				my $new_command = $class_name->new(
    					'base_component' => $self->parent->base_component,
    					'my_config'      => $config
    				);
    				$new_command->controller($self);
				
    				# Determine runpaths
    				foreach my $function ( @{Class::Inspector->functions($class_name)} ) {
    				    my $full_function = $class_name . '::' . $function;
    				    my $coderef = \&$full_function;
				    
    				    # Get subroutine attributes
    				    if ( my $attributes = $new_command->FETCH_CODE_ATTRIBUTES($coderef) ) {
    				        foreach my $attribute ( @{$attributes} ) {
    				            my ( $command, $arguments ) = split( /\s*\(/, $attribute, 2 );
				            
    				            if ( $command eq 'Command' ) {
    				                my $register = '^' . $command_root . ' +' . $function . ' *([^\b]+)*';
    				                if ( $command_name{$register} ) {
    				                    $self->error_override( $class_name, $register )
    			                    } else {
        				                push(
        				                    @run_paths,
        				                    {
        				                        'match'     => $register,
        				                        'function'  => $function
        				                    }
        				                );
    			                    }
				                

    				            } elsif ( $command eq 'CommandRegEx' ) {
    				                $arguments =~ s/\)$//;
    				                unless ( $arguments =~ /^'.*?'$/ ) {
    				                    $self->error_regex( $class_name, $function, $arguments );
    				                } else {
        				                $arguments =~ s/^'(.*?)'$/$1/;
        				                my $register = '^' . $command_root . ' +' . $arguments;
        				                if ( $command_name{$register} ) {
        				                    $self->error_override( $class_name, $register )
        			                    } else {
            				                push(
            				                    @run_paths,
            				                    {
            				                        'match'     => $register,
            				                        'function'  => $function
            				                    }
            				                );
        			                    }
    		                        }
				                    
    				            } elsif ( $command eq 'GlobalRegEx' ) {
    				                $arguments =~ s/\)$//;
    				                unless ( $arguments =~ /^'.*?'$/ ) {
    				                    $self->error_regex( $class_name, $function, $arguments );
    				                } else {
    				                    $arguments =~ s/^'(.*?)'$/$1/;
        				                if ( $command_name{$arguments} ) {
        				                    $self->error_override( $class_name, $arguments )
        			                    } else {
            				                push(
            				                    @run_paths,
            				                    {
            				                        'match'     => $arguments,
            				                        'function'  => $function
            				                    }
            				                );
        			                    }
    				                }
				                
    				            } elsif ( $command eq 'Monitor' ) {
    				                push(
    				                    @run_paths,
    				                    {
    				                        'match'     => '',
    				                        'function'  => $function
    				                    }
    				                );
				                
    				            } elsif ( $command eq 'Event' ) {
    				                $arguments =~ s/\)$//;
    				                $arguments =~ s/^'(.*?)'$/$1/;
    				                push(
    				                    @run_paths,
    				                    {
    				                        'event'     => $arguments,
    				                        'function'  => $function
    				                    }
    				                );
				                
    				            } elsif ( $command eq 'StopAfter' ) {
    				                $end_paths{$function} = 1;
				                
    				            } else {
    				                $self->log->error(
    				                    $class_name . ': Invalid attribute "' . $command . '" on method "' . $function . '", ignoring.'
    				                );
    				            }
    				        }
    				    }
    				}
				
    				# Insert end paths
    				for ( my $i = 0; $i < scalar(@run_paths); $i++ ) {
    				    if ( $end_paths{ $run_paths[$i]->{'function'} } ) {
    				        $run_paths[$i]->{'stop'} = 1;
    				    }
    				}
				
    				$new_command->command_priority('Extension') unless ( $new_command->command_priority );
    				unless ( 
    				    lc($new_command->command_priority) =~ /(extension|last)/
    				    and $self->skip_extensions
    				) {
    					# Add to command structure and name to command map
    					$command{ lc($new_command->command_priority) }->{$class_name} = \@run_paths;
    					$command_name{$class_name} = $new_command;
    					$command_short_name{$command_root} = $new_command;
				
    					$self->log->write( '-> ' . ref($new_command) . ' loaded.' );
    				}
    			}
    		}
    	}
    	close(COMMAND_DIR);
	
        $self->command(\%command);
        $self->command_name(\%command_name);
        $self->command_short_name(\%command_short_name);
    }

    method handle ( whatbot::Message $message, $me? ) {
    	my @messages;
    	foreach my $priority ( qw( primary core extension last ) ) {
    	    last if ( scalar(@messages) and $priority =~ /(extension|last)/ );
	    
	        # Iterate through priorities, in order, check for commands that can
	        # receive content
        	foreach my $command_name ( keys %{ $self->command->{$priority} } ) {
        	    my $command = $self->command_name->{$command_name};
        	    next if ( $command->require_direct and !$message->is_direct );

    	        # Check each method corresponding to a registered runpath to see
    	        # if it cares about our content
        		foreach my $run_path ( @{ $self->command->{$priority}->{$command_name} } ) {
        			next unless ( $run_path->{'match'} );

        		    my $listen = $run_path->{'match'};
        		    my $function = $run_path->{'function'};
    		    
        			if ( $listen eq '' or my (@matches) = $message->content =~ /$listen/i ) {
        				my $result;
        				eval {
        					$result = $command->$function( $message, \@matches );
        				};
        				if ($@) {
        					$self->log->error( 'Failure in ' . $command_name . ': ' . $@ );
        					my $return_message = new whatbot::Message(
        						'from'			 => '',
        						'to'			 => ($message->is_private == 0 ? 'public' : $message->from),
        						'content'		 => $command_name . ' completely failed at that last remark.',
        						'timestamp'		 => time,
        						'base_component' => $self->parent->base_component
        					);
        					push( @messages, $return_message);
					
        				} elsif ( defined $result ) {
        					last if ( $result eq 'last_run' );
					
        					$self->log->write('%%% Message handled by ' . $command_name)
        					    unless ( defined $self->config->io->[0]->{'silent'} );
        					$result = [ $result ] if ( ref($result) ne 'ARRAY' );
    					
        					foreach my $result_single ( @$result ) {
    							my $outmessage;
    							if ( ref($result_single) eq 'whatbot::Message' ) {
    								$outmessage = $result_single;
    								my $content = $outmessage->content;
    								$content =~ s/!who/$message->from/;
    								$outmessage->content($content);
    							} else {
    								$result_single =~ s/!who/$message->from/;
    								$outmessage = new whatbot::Message(
    	        						'from'			    => '',
    	        						'to'				=> ( $message->to eq 'public' ? 'public' : $message->from ),
    	        						'content'			=> $result_single,
    	        						'timestamp'		    => time,
    	        						'base_component'	=> $self->parent->base_component
    	        					);
    							}
            					push( @messages, $outmessage );
    					    }
        				}
    				
        				# End processing for this command if StopAfter was called.
        				last if $run_path->{'stop'};
				
        			}
        		}
        	}
        }
	
    	return \@messages;
    }

	# dear god refactor
    method handle_event ( $event, $user, $me? ) {
    	my @messages;
    	foreach my $priority ( qw( primary core extension last ) ) {
    	    last if ( scalar(@messages) and $priority =~ /(extension|last)/ );
	    
	        # Iterate through priorities, in order, check for commands that can
	        # receive content
        	foreach my $command_name ( keys %{ $self->command->{$priority} } ) {
        	    my $command = $self->command_name->{$command_name};

    	        # Check each method corresponding to a registered runpath to see
    	        # if it cares about our content
        		foreach my $run_path ( @{ $self->command->{$priority}->{$command_name} } ) {
        			next unless ( $run_path->{'event'} and $run_path->{'event'} eq $event );

        		    my $function = $run_path->{'function'};
    				my $result;
    				eval {
    					$result = $command->$function($user);
    				};
    				if ($@) {
    					$self->log->error( 'Failure in ' . $command_name . ': ' . $@ );
    					my $return_message = new whatbot::Message(
    						'from'			 => '',
    						'to'			 => 'public',
    						'content'		 => $command_name . ' completely failed at that last remark.',
    						'timestamp'		 => time,
    						'base_component' => $self->parent->base_component
    					);
    					push( @messages, $return_message);
				
    				} elsif ( defined $result ) {
    					last if ( $result eq 'last_run' );
				
    					$self->log->write('%%% Message handled by ' . $command_name)
    					    unless ( defined $self->config->io->[0]->{'silent'} );
    					$result = [ $result ] if ( ref($result) ne 'ARRAY' );
					
    					foreach my $result_single ( @$result ) {
							my $outmessage;
							if ( ref($result_single) eq 'whatbot::Message' ) {
								$outmessage = $result_single;
								my $content = $outmessage->content;
								$content =~ s/!who/$user/;
								$outmessage->content($content);
							} else {
								$result_single =~ s/!who/$user/;
								$outmessage = new whatbot::Message(
	        						'from'			    => '',
	        						'to'				=> 'public',
	        						'content'			=> $result_single,
	        						'timestamp'		    => time,
	        						'base_component'	=> $self->parent->base_component
	        					);
							}
        					push( @messages, $outmessage );
					    }
    				}
				
    				# End processing for this command if StopAfter was called.
    				last if $run_path->{'stop'};
			
    			}
    		}
        }
	
    	return \@messages;
    }

    method dump_command_map {
        foreach my $priority ( qw( primary core extension ) ) {
    	    my $commands = 0;
	    
    	    $self->log->write( uc($priority) . ':' );
	    
        	foreach my $command_name ( keys %{ $self->command->{$priority} } ) {
        		foreach my $run_path ( @{ $self->command->{$priority}->{$command_name} } ) {
        			if ( $run_path->{'match'} ) {
        				$self->log->write( ' /' . $run_path->{'match'} . '/ => ' . $command_name . '->' . $run_path->{'function'} );
        			} elsif ( $run_path->{'event'} ) {
        				$self->log->write( ' Event "' . $run_path->{'event'} . '" => ' . $command_name . '->' . $run_path->{'function'} );
        			}
        	        
        	        $commands++;
    	        }
    	    }
	    
    	    $self->log->write(' none') unless ($commands);
        }
    }

    method error_override ( Str $class, Str $name ) {
        $self->log->error( $class . ': More than one command being registered for "' . $name . '".' )
    }

    method error_regex ( Str $class, Str $function, Str $regex ) {
        $self->log->error( 
            $class . ': Invalid arguments (' . $regex . ') in method "' . $function . '".'
        );
    }
}

1;

=pod

=head1 NAME

whatbot::Controller - Command processor and dispatcher

=head1 SYNOPSIS

 use whatbot::Controller;
 
 my $controller = new whatbot::Controller;
 $controller->build_command_map();
 
 ...
 
 my $messages = $controller->handle( $incoming_message );

=head1 DESCRIPTION

whatbot::Controller is the master command dispatcher for whatbot. When whatbot
is started, Controller builds the run paths based on the attributes in the
whatbot::Command namespace. When a message event is fired during runtime,
Controller parses the message and directs the event to each appropriate
command.

=head1 INHERITANCE

=over 4

=item whatbot::Component

=over 4

=item whatbot::Controller

=back

=back

=head1 LICENSE/COPYRIGHT

Be excellent to each other and party on, dudes.

=cut
