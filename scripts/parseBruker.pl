#!/usr/bin/env perl 

use warnings;
use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Getopt::Long;
use File::Basename qw/basename/;
use List::Util qw/max/;

# Bring in perl libraries
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib/perl5";

# Optional modules that are not standard
use Spreadsheet::XLSX;
#use Excel::Writer::XLSX;
use Array::IntSpan;

our $VERSION = '3.6.0';

# Expected peaks per serotype
my $peakRanges = Array::IntSpan->new();

# A
$peakRanges->set_range(3280.7,3293.7,"A_intact");
$peakRanges->set_range(996.8 ,1000.8,"A_cleavage_1");
$peakRanges->set_range(2302.9,2312.1,"A_cleavage_2");
# B
$peakRanges->set_range(4018.4,4034.6,"B_intact");
$peakRanges->set_range(1756.5,1763.5,"B_cleavage_1");
$peakRanges->set_range(2277.7,2286.9,"B_cleavage_2");
# E
$peakRanges->set_range(3607.8,3622.2,"E_intact");
$peakRanges->set_range(1129.2,1133.8,"E_cleavage_1");
$peakRanges->set_range(2493.6,2503.6,"E_cleavage_2");
# F
$peakRanges->set_range(5100.8,5121.2,"F_intact");
$peakRanges->set_range(1342.5,1347.9,"F_cleavage_1");
$peakRanges->set_range(3777.3,3792.5,"F_cleavage_2");
# F5
$peakRanges->set_range(5100.8,5121.2,"F5_intact");
$peakRanges->set_range(1870.3,1877.7,"F5_cleavage_1");
$peakRanges->set_range(3248.5,3261.5,"F5_cleavage_2");

my @subtype      = qw(A B E F F5);
my @cleavageType = qw(cleavage_1 cleavage_2 intact);
my %peakMeaning;
# Combine @subtype and @cleavageType into a header
my @typingHeader;
for my $type(@subtype){
  for my $cleavageType(@cleavageType){
    my $peakHeader = $type."_".$cleavageType;
    my $snHeader   = "SN_".$type."_".$cleavageType;

    push(@typingHeader, $peakHeader);
    push(@typingHeader, $snHeader);

    if($peakHeader =~ /_cleavage/i){
      $peakMeaning{$peakHeader} = $type;
    }
  }
}

# Default peak struct
my $defaultPeakStruct = {
  SN           => -1,
  fullNameType => "",
  peak         => -1,
  serotypeLabel=> "",
  type         => "",
};

local $0 = basename $0;
sub logmsg{local $0=basename $0; print STDERR "$0: @_\n";}
exit(main());

sub main{
  my $settings={};
  GetOptions($settings,qw(version help)) or die $!;
  version() if($$settings{version});
  usage() if($$settings{help} || !@ARGV);

  # print off the output header
  print "plate\tsample\tinferred_type\tnumAcquisitions\t";
  print join("\t",@typingHeader);
  print "\n";

  # Start off the basic workflow
  for my $spreadsheet(@ARGV){
    my $tsv = readRawSpreadsheet($spreadsheet, $settings);
    
    for my $plate(sort keys(%$tsv)){
      my $plateEntries = $$tsv{$plate};
      # Loop through the samples but sort them alphabetically
      my @sampleName = sort {$a cmp $b} keys(%$plateEntries);
      for my $sample(@sampleName){
        my $sampleInfo = $$plateEntries{$sample};
        
        # Start off printing the row of information
        print "$plate\t$sample";

        # Get each acquisition's profile and see if they
        # agree with the first acquisition.
        my %acquisitionProfile;
        my $refSubtype = $$sampleInfo{serotypeInferrence}[0];
        my @refSubtype = sort{$a cmp $b} grep{$$refSubtype{$_}==1} keys(%$refSubtype);
        my $inferredType = join(",",@refSubtype);
        my $numConflictingAcquisitions = 0;
        
        # shortcut: just see if acquisitions after the first
        # are in conflict.
        # TODO: also see if other acquisitions have new subtypes
        # not found in the first.
        for my $subtype(@refSubtype){
          for (my $j=1;$j<$$sampleInfo{numAcquisitions};$j++){
            $$sampleInfo{serotypeInferrence}[$j]{$subtype} //= 0;
            if($$sampleInfo{serotypeInferrence}[$j]{$subtype} != 1){
              $numConflictingAcquisitions++;
            }
          }
        }
        if($numConflictingAcquisitions){
          $inferredType.=" (inconclusive: $numConflictingAcquisitions conflicts)";
        }
        print "\t$inferredType";
        print "\t".$$sampleInfo{numAcquisitions};

        # The rest of the headers
        for my $subtype(@subtype){
          for my $cleavageType(@cleavageType){
            my $peakHeader = $subtype."_".$cleavageType;
            my $snHeader   = "SN_".$subtype."_".$cleavageType;

            # For simplicity, just report the first acquisition
            my $thisPeak = $$sampleInfo{peaks}{$peakHeader}[0] || $defaultPeakStruct;
            print "\t"
                . $$thisPeak{peak}
                . "\t"
                . $$thisPeak{SN}
                . "";
          }
        }



        print "\n";
      }
    }

  }

  return 0;
}

sub readRawSpreadsheet{
  my($spreadsheet, $settings) = @_;
  
  # https://metacpan.org/pod/Spreadsheet::XLSX
  my $excel = Spreadsheet::XLSX->new($spreadsheet);

  my %peakInfo;

  # Must remove randomness
  my @sheet = sort{$$a{path} cmp $$b{path}} @{$excel->{Worksheet}};
  foreach my $sheet (@sheet){
    #printf("Sheet: %s\n", $sheet->{Name});
    my %tsv;

    # Initialize variables for columns in the
    # single-sheet intermediate file
    my($date, $plate, $sample,$Peak_1_A, $sn_Peak_1_A, $Peak_2_A, $sn_Peak_2_A, $Intact_A, $sn_Intact_A, $Peak_1_B, $sn_Peak_1_B, $Peak_2_B, $sn_Peak_2_B, $Intact_B, $sn_Intact_B, $Peak_1_E, $sn_Peak_1_E, $Peak_2_E, $sn_Peak_2_E, $Intact_E, $sn_Intact_E, $Peak_1_F, $sn_Peak_1_F, $Peak_2_F, $sn_Peak_2_F, $Intact_F, $sn_Intact_F);

    my @header; #header columns

    $sheet -> {MaxRow} ||= $sheet -> {MinRow};
    $sheet -> {MaxCol} ||= $sheet -> {MinCol};
        
    # Loop through the rows
    $sheet -> {MaxRow} ||= $sheet -> {MinRow};
    ROW:
    for(my $row=$sheet->{MinRow}; $row<=$sheet->{MaxRow}; $row++){
      
      # mark if we are looking at the header row
      my $rowkey; # index of this row will be m/z
      my %tsvrow; # This TSV's row
        
      # Loop through the columns of the row
      COL:
      for(my $col=$sheet->{MinCol}; $col<=$sheet->{MaxCol}; $col++){
               
        my $cell = $sheet->{Cells}[$row][$col];
        # I don't care much about blank cells for this analysis
        next if(!$cell);

        # Extract the cell's value for readability
        my $value = $$cell{Val};
        $value =~ s/^\s+|\s+$//g; # whitespace trim

        # Parse the line with Spectrum: D:\Data\CLIA\2020\02-21-20\Plate 169380\2000001 Pl-6-A\0_A3\1\1SLin
        if($value =~ /Plate\s+(.+?)\\(.+?)\\/){
          $plate  = $2;
          $sample = $1;
        }

        # We're looking at the header row if we come across m/z
        if(lc($value) eq 'm/z'){
          @header = map{$_->{Val}} @{ $$sheet{Cells}[$row] };
          next ROW;
        }

        # If headers are already defined, then we're looking at values
        # and let's set those values in a hash.
        if(@header){
          my @tsvValue;
          while($col <= $sheet->{MaxCol}){
            $tsvValue[$col] = $sheet->{Cells}[$row][$col]{Val};
            $tsvValue[$col] //= "";
            # whitespace trim
            $tsvValue[$col] =~ s/^\s+|\s+$//g;
            $col++;
          }
          @tsvrow{@header} = @tsvValue;
          $tsvrow{row} = $row;
          $tsv{$tsvValue[0]} = \%tsvrow;
          #push(@{ $tsv{$tsvValue[0]} }, \%tsvrow);
          #die Dumper $tsvValue[0],\%tsvrow;
          next ROW;
        }
      }

    }

    if(keys(%tsv)){
      if(!$plate){
        die "ERROR: did not find plate ID on tab ".$sheet->{Name};
      }
      if(!$sample){
        die "ERROR: did not find bot ID on tab ".$sheet->{Name};
      }

      # There are multiple acquisitions per sample per
      # plate and so it needs to be captured in an array.
      push(@{ $peakInfo{$sample}{$plate} }, \%tsv);
    }
  }
  #print Dumper \%peakInfo;exit 0;
  #die Dumper keys(%{ $peakInfo{157016} });

  # Turn this into a 25+ column format with each peak info shown on each plate/sample combo line
  my %finalTsv;
  while(my($plate, $plateInfo) = each(%peakInfo)){
    my @sampleAndSrotype = sort keys(%$plateInfo);
    for my $sampleAndSerotype(@sampleAndSrotype){
      my $sampleInfoArr = $$plateInfo{$sampleAndSerotype};
      my($sample, $serotype) = split(/\-/, $sampleAndSerotype);
      next if(!$serotype);
      for my $sampleInfo(sort @$sampleInfoArr){
        my @peak;
        my @sortedPeakInfo = sort {
          $$sampleInfo{$a}{row}||=0;
          $$sampleInfo{$b}{row}||=0;
          $$sampleInfo{$a}{row} <=> $$sampleInfo{$b}{row}
        } values(%$sampleInfo);
        for my $peak(sort @sortedPeakInfo){
          # Find which type this belongs to based on ranges of m/z
          my $fullNameType = $peakRanges->lookup($$peak{'m/z'});
          # If not found in the ranges, UNDEFINED
          next if(!defined($fullNameType));
          $fullNameType||="UNDEFINED_PEAK";

          my $type = $peakMeaning{$fullNameType} || "";

          # Record this peak under the right type
          my %info = (
            peak  => $$peak{'m/z'},
            SN    => $$peak{SN},
            type  => $type,
            fullNameType => $fullNameType,
            serotypeLabel => $serotype,
            #serotype => $serotype,
          );

          # There are multiple acquisitions per sample per
          # plate and so each peak could have multiple
          # values; transform these data into an array.
          #$finalTsv{$plate}{$sample}{$type} = \%info;
          push(@{ $finalTsv{$plate}{$sample}{peaks}{$fullNameType} }, \%info);

          if($type && $fullNameType =~ /cleavage/i){
            #push(@{ $finalTsv{$plate}{$sample}{serotypeInferrence} }, $type);

            my $acquisitionNum = scalar(@{ $finalTsv{$plate}{$sample}{peaks}{$fullNameType} }) - 1;
            $finalTsv{$plate}{$sample}{serotypeInferrence}[$acquisitionNum]{$type} = 1;
          }
        }
      }
    }
  }

  # Keep the data structure stable by sorting
  while(my($plate, $plateInfo) = each(%finalTsv)){
    my @sampleName = sort keys(%$plateInfo);
    for my $sample(@sampleName){
      my $sampleInfo = $$plateInfo{$sample};
      #$finalTsv{$plate}{$sample}{peaks} = 
      #  [sort {$$b{peak} <=> $$a{peak} || $$a{SN} <=> $$b{SN}}
      #    @{$finalTsv{$plate}{$sample}{peaks}}];
      #$finalTsv{$plate}{$sample}{acquisitions} =
      #  [sort {$a cmp $b}
      #    @{$finalTsv{$plate}{$sample}{acquisitions}}];
      
      # How many acquisitions were there for this sample?
      my $numAcquisitions = 0;
      my @peakType = sort keys %{ $$sampleInfo{peaks} };
      for my $peakType(@peakType){

        # Sort each peak by peak
        $$plateInfo{$sample}{peaks}{$peakType} =
          [sort {$$a{peak} <=> $$b{peak}}
            @{ $$plateInfo{$sample}{peaks}{$peakType} }];
        # Number of acquisitions will be the lowest number seen so far
        # or the number of peaks found here for this peak type,
        # whichever is higher.
        $numAcquisitions = max($numAcquisitions, scalar(@{ $$sampleInfo{peaks}{$peakType} }));
      }
      $$sampleInfo{numAcquisitions} = $numAcquisitions;
    }
  }
  #print Dumper \%finalTsv; exit 0;

  return \%finalTsv;
}

sub version{
  print "$0 $VERSION";
  exit 0;
}

sub usage{
  print
  "$0: runs the endopep peaks workflow
  Usage: $0 [options] spreadsheet.xlsx [spreadsheet2.xlsx...]
  --help     This useful help menu
  --version  Print the version and exit
";
  exit 0;
}

