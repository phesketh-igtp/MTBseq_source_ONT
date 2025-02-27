#!/usr/bin/env perl

package TBminimap2;

use strict;
use warnings;
use File::Copy;
use TBtools;
use Exporter;
use vars qw($VERSION @ISA @EXPORT);

$VERSION =  1.0.2;
@ISA     =  qw(Exporter);
@EXPORT  =  qw(tbminimap2);

sub tbminimap2 {
   # get parameter and input from front-end.
   my $logprint         =  shift;
   my $W_dir            =  shift;
   my $VAR_dir          =  shift;
   my $MINIMAP2_dir     =  shift;
   my $SAMTOOLS_dir     =  shift;
   my $MINIMAP2_call    =  shift;
   my $SAMTOOLS_call    =  shift;
   my $BAM_OUT          =  shift;
   my $ref              =  shift;
   my $threads          =  shift;
   my $naming_scheme    =  shift;
   my @fastq_files      =  @_;
   my %input;

   # start logic...
   foreach my $file (sort { $a cmp $b } @fastq_files) {
      my @file_name        =  split(/_/,$file);
      my $sampleID         =  shift(@file_name);
      my $libID            =  shift(@file_name);
      my $file_mod         =  join("_",@file_name);
      die("wrong file name ($file_mod)") if not $file_mod =~ s/(R1|R2).f(ast)?q.gz//;
      my $dir              =  $1;
      my $machine          =  $file_mod;
      my $fullID           =  join("_",($sampleID,$libID));
      if($machine ne ""){
         my $machine_new   =  substr($machine,0,(length($machine)-1));
         $fullID           .= "_".$machine_new;
      }
      $input{$fullID}{$dir}{fastq}     =  $file;
      $input{$fullID}{$dir}{sampleID}  =  $sampleID;
      $input{$fullID}{$dir}{libID}     =  $libID;
      $input{$fullID}{$dir}{machine}   =  $machine;
   }
   @fastq_files = ();
   foreach my $fullID (sort { $a cmp $b } keys %input) {
      my $sampleID;
      my $libID;
      my $files_string        =  "";
      my @dirs                =  sort(keys %{$input{$fullID}});
      foreach my $dir (sort { $a cmp $b } @dirs) {
         my $file             =  $input{$fullID}{$dir}{fastq};
         $sampleID            =  $input{$fullID}{$dir}{sampleID};
         $libID               =  $input{$fullID}{$dir}{libID};
         $files_string        .= " $W_dir/$file";
      }
      @dirs                   =  ();
      my $read_naming_scheme  =  "\'\@RG\\tID:$fullID\\tSM:$sampleID\\tPL:Illumina\\tLB:$libID\'";
      my $logfile             =  $fullID . ".bamlog";
      my $commandline         =  "";
      unlink("$BAM_OUT/$logfile");
      print $logprint "<INFO>\t",timer(),"\tFound at most two files for $fullID!\n";
      # index reference with minimap2, if it isn't indexed already.
      unless(-f "$VAR_dir/$ref.amb" && -f "$VAR_dir/$ref.ann" && -f "$VAR_dir/$ref.bwt" && -f "$VAR_dir/$ref.pac" && -f "$VAR_dir/$ref.sa"){
         print $logprint "<INFO>\t",timer(),"\tStart indexing reference genome $ref...\n";
         print $logprint "<INFO>\t",timer(),"\t$MINIMAP2_call index $VAR_dir/$ref >> $BAM_OUT/$logfile\n";
         $commandline = "$MINIMAP2_call index $VAR_dir/$ref 2>> $BAM_OUT/$logfile";
         system($commandline)==0 or die "$commandline failed: $?\n";
         print $logprint "<INFO>\t",timer(),"\tFinished indexing reference genome $ref!\n";
      }
      # map reads with minimap2 and -t parameter.
      print $logprint  "<INFO>\t",timer(),"\tStart MINIMAP2 mapping for $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$MINIMAP2_call -ax map-ont -t $threads $VAR_dir/$ref $files_string > $BAM_OUT/$fullID.sam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$MINIMAP2_call mem -t $threads -R $read_naming_scheme $VAR_dir/$ref $files_string > $BAM_OUT/$fullID.sam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished MINIMAP2 mapping for $fullID!\n";
      # convert from .sam to .bam format with samtools -S (sam input) and (-b bam output) and -T (reference).
      print $logprint "<INFO>\t",timer(),"\tStart using samtools to convert from .sam to .bam for $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$SAMTOOLS_call view -@ $threads -b -T $VAR_dir/$ref -o $BAM_OUT/$fullID.bam $BAM_OUT/$fullID.sam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$SAMTOOLS_call view -@ $threads -b -T $VAR_dir/$ref -o $BAM_OUT/$fullID.bam $BAM_OUT/$fullID.sam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished file conversion for $fullID!\n";
      # sort with samtools.
      print $logprint "<INFO>\t",timer(),"\tStart using samtools for sorting of $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$SAMTOOLS_call sort -@ $threads -T /tmp/$fullID.sorted -o $BAM_OUT/$fullID.sorted.bam $BAM_OUT/$fullID.bam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$SAMTOOLS_call sort -@ $threads -T /tmp/$fullID.sorted -o $BAM_OUT/$fullID.sorted.bam $BAM_OUT/$fullID.bam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished using samtools for sorting of $fullID!\n";
      # indexing with samtools.
      print $logprint "<INFO>\t",timer(),"\tStart using samtools for indexing of $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$SAMTOOLS_call index -b $BAM_OUT/$fullID.sorted.bam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$SAMTOOLS_call index -b $BAM_OUT/$fullID.sorted.bam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished using samtools for indexing of $fullID!\n";
      # removing pcr duplicates with samtools.
      print $logprint "<INFO>\t",timer(),"\tStart removing putative PCR duplicates from $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$SAMTOOLS_call rmdup $BAM_OUT/$fullID.sorted.bam $BAM_OUT/$fullID.nodup.bam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$SAMTOOLS_call rmdup $BAM_OUT/$fullID.sorted.bam $BAM_OUT/$fullID.nodup.bam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished removing putative PCR duplicates for $fullID!\n";
      # recreate index with samtools.
      print $logprint "<INFO>\t",timer(),"\tStart recreating index for $fullID...\n";
      print $logprint "<INFO>\t",timer(),"\t$SAMTOOLS_call index -b $BAM_OUT/$fullID.nodup.bam 2>> $BAM_OUT/$logfile\n";
      $commandline = "$SAMTOOLS_call index -b $BAM_OUT/$fullID.nodup.bam 2>> $BAM_OUT/$logfile";
      system($commandline)==0 or die "$commandline failed: $?\n";
      print $logprint "<INFO>\t",timer(),"\tFinished recreating index for $fullID!\n";
      # removing temporary files.
      print $logprint "<INFO>\t",timer(),"\tRemoving temporary files...\n";
      unlink("$BAM_OUT/$fullID.sam");
      unlink("$BAM_OUT/$fullID.bam");
      unlink("$BAM_OUT/$fullID.sorted.bam");
      unlink("$BAM_OUT/$fullID.sorted.bam.bai");
      # renaming files.
      move("$BAM_OUT/$fullID.nodup.bam","$BAM_OUT/$fullID.bam")            || die print $logprint "<ERROR>\t",timer(),"\tmove failed: TBminimap2.pm line: ", __LINE__ , " \n";
      move("$BAM_OUT/$fullID.nodup.bam.bai","$BAM_OUT/$fullID.bam.bai")    || die print $logprint "<ERROR>\t",timer(),"\tmove failed: TBminimap2.pm line: ", __LINE__ , " \n";
      # finished.
      print $logprint "<INFO>\t",timer(),"\tFinished mapping for $fullID!\n";
   }
   undef(%input);
}

1;
