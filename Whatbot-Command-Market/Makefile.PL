use inc::Module::Install;

# Define metadata
name     'Whatbot-Command-Market';
all_from 'lib/Whatbot/Command/Market.pm';
author   'Nicholas Melnick <nick@abstractwankery.com>';
license  'perl';

# Specific dependencies
requires      'Whatbot'              => 0.12;
requires      'Moose'                => 2.04;
requires      'namespace::autoclean' => 0;
requires      'String::IRC'          => 0.04;
requires      'HTML::TreeBuilder::XPath' => 0.14;

test_requires 'Test::More'           => 0;
test_requires 'DBD::SQLite'          => 0;

WriteAll;
