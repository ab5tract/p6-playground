
sub check-whitelist($v) {
    (% //= (@whitelist X=> True)){$v} // False
}





# screenshot code blocks from the presentation.


my %lookup = @whitelist X=> True;
sub check-whitelist($v) {
    %lookup{$v} // False
}





my $lookup = @whitelist.Set;
sub check-whitelist($v) {
    $lookup{$v} // False
}
















my %lookup;
%lookup{$_} = 1 for @whitelist;
sub check_whitelist {
    $lookup{$_[0]} // 0
}







my $lookup = @whitelist.Set;
sub check-whitelist($v) {
    $lookup (cont) $v
}




my $lookup = Map.new: @whitelist Z=> 1..*;
sub check-whitelist($v) {
    $lookup{$v}
}



my $lookup = Map.new: @whitelist Z=> 1..*;
sub check-whitelist($v) {
    so %lookup{$v}
}
