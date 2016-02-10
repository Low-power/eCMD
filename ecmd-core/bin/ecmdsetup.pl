#!/usr/bin/perl
# File ecmdsetup.pl created by Jason Albert,6A5244 at 13:50:19 on Fri May 13 2005. 

# Why wouldn't you use strict???
use strict;
use Cwd 'chdir';
##########################################################################
# Figure out where the user is calling this script from
#

# return value
my $rc = 0;

my $callingPwd;
my $pwd;

BEGIN {
  # Meghna needs me to save away the directory the script was called from, I'll do that here
  #Commenting this since this seems to be resolving the links in the path
  #chomp($callingPwd = `pwd`);
  #This seems to keep the directory intact. Tested in ksh, Jason will test in csh
  chomp($callingPwd = `cd .;pwd`);
  # Now do the rest
  my @tempArr = split(/\/+/,$0);
  pop(@tempArr); # The script name
  $" = "/"; # Make it so the array below seperates on / instead of space
  #If it starts with a ., it's being called with relative path
  if (substr($0,0,1) ne "/") {
    $pwd = $callingPwd;  # Get where I got called from
    $pwd = $pwd . "/" . "@tempArr";  # Now use the relative to find out where the script is 
  } else { # Absolute path
    $pwd = "@tempArr";
  }
  $" = " "; # Reset
  chomp($pwd = `cd $pwd;pwd`);  # Get to where this script resides

  # This is a slick bit of trickeration if I may say so myself.
  # We have to change to the directory the script is in for the module requires below
  # This will enable the modules to be found in the local directory in the @INC
  chdir "$pwd";
}

# installpath points to root of install
my $installPath = $pwd;
$installPath =~ s/\/([^\/..]*\/?)$/\//;
# Remove the trailing slash if there
$installPath =~ s/\/$//;


#########################################
# Setup the modules to include
# Base support, always there
use ecmdsetup;
my $ecmd = new ecmdsetup();

# Any installed plugins are located a dir below where this script resides
# use lib that path so we can load those modules
# The load all those instances into a plugin hash that is used thru out
# This allows the code to be adaptable to any number of plugins
use lib "$pwd/plugins";

my %plugins;
my $pluginKey;

# Get a list of all plugins installed
my @tempArr = split(/\s+/, `ls $pwd/plugins`);

# Loop over that list and load everything in
for (my $x=0; $x <= $#tempArr; $x++) {
  # Create the key into the hash and the name of the module to load
  $pluginKey = $tempArr[$x];
  my $pluginSetup = $tempArr[$x];
  $pluginKey =~ s/setup.pm//g;
  $pluginSetup =~ s/.pm//g;
  # Load the module and create the object
  eval "require $pluginSetup";
  $plugins{$pluginKey} = new $pluginSetup();
}

##########################################################################
#  Variables
#
my %modified;  # 0 is no change, 1 set needed, -1 unset needed
my $shell;
my $release;
my $prevRelease;
my $plugin;
my $product;
my $bits = 64;
my $arch;
my $temp;
my $shortcut = 0;
my $localInstall = 1;  # Assume it's a local install and then disprove it by comparing ctepaths to CTEPATH
my $copyLocal = 0;  # Does the user want ECMD_EXE and ECMD_DLL_FILE copied to /tmp and run from there?
my $cleanup = 0;  # Call only cleanup on the plugins to remove anything they might have put out there.
# These ctepaths are in regular expression format for the search below.
# This allows the user to put just rchland or rchland.ibm.com, etc..
my @ctepaths = ("/afs/rchland(|\.ibm\.com)/rel/common/cte",
                "/afs/awd(|\.austin\.ibm\.com)/projects/cte",
                "/afs/austin(|\.ibm\.com)/projects/cte",
                "/afs/apd(|\.pok\.ibm\.com)/func/vlsi/cte",
                "/afs/(bb|(vlsilab(|\.boeblingen\.ibm\.com)))/proj/cte",
                "/afs/btv(|\.ibm\.com)/data/vlsi/cte",
                "/afs/raleigh(|\.ibm\.com)/cadtools/cte",
                "/afs/watson(|\.ibm\.com)/projects/vlsi/cte");

#####################################################
# Call the main function, then add the rc from that to the output
#
$rc = main();
# Yet again, csh sucks and doesn't have a return value.  They will have to go without
if ($shell eq "ksh") {
  printf("return $rc;");
}
exit($rc);

sub main {
  #####################################################
  # Look to see if help was requested
  #
  if ("@ARGV" =~ /-h/) {
    help();
    foreach $pluginKey ( keys %plugins ) {
      $pluginKey->help();
    }
    return 1;
  }

  ##########################################################################
  # Figure out if the user is on a local copy of CTE
  #
  for (my $x = 0; $x <= $#ctepaths && $localInstall != 0; $x++) {
    if ($ENV{"CTEPATH"} =~ m!${ctepaths[$x]}!) {
      $localInstall = 0;
    }
  }

  ##########################################################################
  # Get the users shell
  #
  $shell = shift(@ARGV);

  # If you add a shell here, you need to update the output printing below
  if ($shell eq "ksh") {
  } elsif ($shell eq "csh") {
  } else {
    ecmd_print("Your shell is unsupported!", 1);
    return 1;
  }

  ##########################################################################
  # Get the release
  #

  # Save the previous release the user may have had
  $prevRelease = $ENV{"ECMD_RELEASE"};

  $release = shift(@ARGV);

  # Here is where we put in the magic to allow the user to just put a period to cover all four ecmd parms
  if ($release eq ".") {
    if ($ENV{"ECMD_RELEASE"} eq "" || $ENV{"ECMD_PLUGIN"} eq "" || $ENV{"ECMD_PRODUCT"} eq "" || $ENV{"ECMD_ARCH"} eq "") {
      ecmd_print("You can't specify the '.' shortcut without having specified the release, product and plugin previously!", 1);
      return 1;
    } else {
      $shortcut = 1;
    }
  }

  if ($shortcut) {
    $release = $ENV{"ECMD_RELEASE"};
  }

  # We'll see if the release is supported based upon the existence of the bin directory
  if ($release ne "auto" && !$localInstall) {
    $temp = $ENV{"CTEPATH"} . "/tools/ecmd/" . $release . "/bin";
    if (!(-d $temp)) {
      ecmd_print("The eCMD release '$release' you specified is not known!", 1);
      return 1;
    }
  }

  ##########################################################################
  # Get the plugin
  #
  if ($shortcut) {
    $plugin = $ENV{"ECMD_PLUGIN"};
  } else {
    $plugin = shift(@ARGV);
  }
  # See if the plugin passed in matches any of the ones we have modules for
  my $pluginFound = 0;
  foreach $pluginKey ( keys %plugins ) {
    if ($pluginKey eq $plugin) {
      $pluginFound = 1;
    }
  }
  if ($pluginFound == 0) {
    ecmd_print("The eCMD plugin '$plugin' you specified is not known!", 1);
    return 1;
  }


  ##########################################################################
  # Get the product
  #
  if ($shortcut) {
    $product = $ENV{"ECMD_PRODUCT"};
  } else {
    $product = shift(@ARGV);
  }

  ##########################################################################
  # Loop through the args left and see if any are for ecmd
  #
  for (my $x = 0; $x <= $#ARGV;) {
    if ($ARGV[$x] eq "copylocal") {
      $copyLocal = 1;
      splice(@ARGV,$x,1);  # Remove so plugin doesn't see it
    } elsif ($ARGV[$x] eq "cleanup") {
      $cleanup = 1;
      ecmd_print("Removing eCMD and Plugin settings from environment", 1);
      splice(@ARGV,$x,1);  # Remove so plugin doesn't see it
    } elsif ($ARGV[$x] eq "64") {   
	$bits = 64;
	splice(@ARGV,$x,1);  # Remove so plugin doesn't see it
    } elsif ($ARGV[$x] eq "32") {   
	$bits = 32;
	splice(@ARGV,$x,1);  # Remove so plugin doesn't see it
    } elsif ($ARGV[$x] eq "quiet") {
	$ecmdsetup::quiet = 1;
	splice(@ARGV,$x,1);  # Remove so plugin doesn't see it
    } else {
      # We have to walk the array here because the splice shortens up the array
      $x++;
    }
  }

  ##########################################################################
  # Determine the desired architecture for $ECMD_ARCH
  #
  if ($shortcut) {
    $arch = $ENV{"ECMD_ARCH"};
  } else {
    # AIX
    if (`uname` eq "AIX\n") {
      if ($bits eq "32") {
        $arch = "aix";
      }
      elsif ($bits eq "64") {
        $arch = "aix64";
      }
      else {
        ecmd_print("'$bits' is not a valid bit value!", 1);
        return 1;
      }
      # PPC
    } elsif (`uname -a|grep ppc` ne "") {
      if ($bits eq "32") {
        $arch = "ppc";
      }
      elsif ($bits eq "64") {
        $arch = "ppc64";
      }
      else {
        ecmd_print("'$bits' is not a valid bit value!", 1);
        return 1;
      }
      # X86
    } else {
      if ($bits eq "32") {
        $arch = "x86";
      }
      elsif ($bits eq "64") {
        $arch = "x86_64";
      }
      else {
        ecmd_print("'$bits' is not a valid bit value!", 1);
        return 1;
      }    
    }
  }

  ##########################################################################
  # Cleanup any ecmd bin dirs that might be in the path
  #
  # Pull out any of the matching cases
  # This expression matches anything after a : up to /tools/ecmd/<anything>/bin and then a : or end of line
  if ($localInstall) {
    $ENV{"PATH"} =~ s!$installPath/$arch/bin!:!g;
    $ENV{"PATH"} =~ s!$installPath/bin!:!g;
  } else {
    $ENV{"PATH"} =~ s!([^:]*?)/tools/ecmd/([^\/]*?)/$arch/bin(:|$)!:!g;
    $ENV{"PATH"} =~ s!([^:]*?)/tools/ecmd/([^\/]*?)/bin(:|$)!:!g;
  }
  # We might have left a : on the front, remove it
  $ENV{"PATH"} =~ s/^://g;
  # Same with the back, might have left a :
  $ENV{"PATH"} =~ s/:$//g;
  # Any multiple : cases, reduce to one
  $ENV{"PATH"} =~ s/(:+)/:/g;
  # Now mark the path modifed
  $modified{"PATH"} = 1;

  ##########################################################################
  # Call cleanup on plugins
  #

  # Only do this if the plugin has changed from last time
  if ($ENV{"ECMD_PLUGIN"} ne $plugin || $cleanup) {
    foreach $pluginKey ( keys %plugins ) {
      $rc = $plugins{$pluginKey}->cleanup(\%modified);
      if ($rc) {
        return $rc;
      }
    }
  }

  ##########################################################################
  # Set ECMD_HOME based upon the installPath figured out above
  #
  $ENV{"ECMD_HOME"} = $installPath;
  $modified{"ECMD_HOME"} = 1;

  ##########################################################################
  # Flag the ECMD_* variables as modified if appropriate
  #
  if (!$shortcut) {
    $ENV{"ECMD_RELEASE"} = $release;
    $modified{"ECMD_RELEASE"} = 1;
    $ENV{"ECMD_PLUGIN"} = $plugin;
    $modified{"ECMD_PLUGIN"} = 1;
    $ENV{"ECMD_PRODUCT"} = $product;
    $modified{"ECMD_PRODUCT"} = 1;
    $ENV{"ECMD_ARCH"} = $arch;
    $modified{"ECMD_ARCH"} = 1;
  }
  if ($cleanup) {
    $modified{"ECMD_RELEASE"} = -1;
    $modified{"ECMD_PLUGIN"} = -1;
    $modified{"ECMD_PRODUCT"} = -1;
    $modified{"ECMD_ARCH"} = -1;
    $modified{"ECMD_HOME"} = -1;
  }

  ##########################################################################
  # Call setup on plugin specified
  #
  if (!$cleanup) {
    foreach $pluginKey ( keys %plugins ) {
      if ($plugin eq $pluginKey) { # Only call setup on our selected plugin
        $rc = $plugins{$pluginKey}->setup(\%modified,
                                          { ARGV => "@ARGV",
                                            localInstall => $localInstall,
                                            arch => $arch,
                                            product => $product,
                                            ecmd => "ecmd",
                                            callingPwd => $callingPwd,
                                            installPath => $installPath,
                                          });
        if ($rc) {
          return $rc;
        }
      }
    }
  }

  ##########################################################################
  # Add bin directory to path
  #
  if (!$cleanup) {
    if ($localInstall) {
      $ENV{"PATH"} = $installPath . "/bin:" . $ENV{"PATH"};
      $ENV{"PATH"} = $installPath . "/" . $arch . "/bin:" . $ENV{"PATH"};
    } else {
      $ENV{"PATH"} = $ENV{"CTEPATH"} . "/tools/ecmd/" . $ENV{"ECMD_RELEASE"} . "/bin:" . $ENV{"PATH"};
      $ENV{"PATH"} = $ENV{"CTEPATH"} . "/tools/ecmd/" . $ENV{"ECMD_RELEASE"} . "/" . $arch . "/bin:" . $ENV{"PATH"};
    }
    $modified{"PATH"} = 1;
  }

  ##########################################################################
  # Updates setup scripts if release changed
  # All we need to do is resource the setup scripts
  #
  if (($prevRelease ne $ENV{"ECMD_RELEASE"}) && !$localInstall) {
    my $file;
    if ($shell eq "csh") {
      $file = sprintf("%s/tools/ecmd/%s/bin/ecmdaliases.csh", "\$CTEPATH", $ENV{"ECMD_RELEASE"});
      printf("source $file;");
    } else {
      $file = sprintf("%s/tools/ecmd/%s/bin/ecmdaliases.ksh", "\$CTEPATH", $ENV{"ECMD_RELEASE"});
      printf(". $file;");
    }
  }

  ####################################################
  # Do the copy to /tmp if local was given
  #
  if ($copyLocal) {
    my $command;
    my @tempArr;
    if ($cleanup) {
      ecmd_print("Removing directory /tmp/\$ECMD_TARGET/");
      $command = "rm -r /tmp/" . $ENV{"ECMD_TARGET"};
      system("$command");
    } else {
      ecmd_print("Copying ECMD_EXE and ECMD_DLL_FILE to /tmp/\$ECMD_TARGET/");
      $command = "/tmp/" . $ENV{"ECMD_TARGET"};
      if (!(-d $command)) { #if the directory isn't there, create it
        $command = "mkdir " . $command;
        system("$command");
      }
      @tempArr = split(/\//,$ENV{"ECMD_EXE"});
      $command = "cp " . $ENV{"ECMD_EXE"} . " /tmp/" . $ENV{"ECMD_TARGET"} . "/" . $tempArr[$#tempArr];
      system("$command");
      $ENV{"ECMD_EXE"} = "/tmp/" . $ENV{"ECMD_TARGET"} . "/" . $tempArr[$#tempArr];
      $modified{"ECMD_EXE"} = 1;
      @tempArr = split(/\//,$ENV{"ECMD_DLL_FILE"});
      $command = "cp " . $ENV{"ECMD_DLL_FILE"} . " /tmp/" . $ENV{"ECMD_TARGET"} . "/" . $tempArr[$#tempArr];
      system("$command");
      $ENV{"ECMD_DLL_FILE"} = "/tmp/" . $ENV{"ECMD_TARGET"} . "/" . $tempArr[$#tempArr];
      $modified{"ECMD_DLL_FILE"} = 1;
    }
  }

  ##########################################################################
  # Write out the modified environment
  #
  $ecmd->write_environment($shell,\%modified);
}

#  Umm.. yeah.. I'm going to need you to work this weekend on the help text.  Mkay..
sub help {
  ecmd_print("ecmdsetup <release> <plugin> <product> [32|64] [copylocal] [cleanup] <plugin options>");
  ecmd_print("<release> - Any eCMD Version currently supported in CVS (ex rel, ver5, ver4-3)");
  ecmd_print("<plugin> - varies based upon your ecmd install");
  ecmd_print("<product> - varies based upon plugin");
  ecmd_print("[32|64] - Use the 32 or 64-bit versions of eCMD and plugins.  Defaults to 64.");
  ecmd_print("[copylocal] - Copy the \$ECMD_EXE and \$ECMD_DLL_FILE to /tmp/\$ECMD_TARGET/");
  ecmd_print("[cleanup] - Remove all eCMD and Plugin settings from environment");
  ecmd_print("[quiet] - Disables status output");
  ecmd_print("<plugin options> - anything else passed into the script is passed onto the plugin");
  ecmd_print("-h - this help text");
}
