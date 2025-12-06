module std::regex;


faultdef NO_MATCH;
<*
    An interface for a regex implementation, done such that making compiled regular expressions can be much easier in the future
*>
interface Regex {
    <*
        @param view "The string view being matched over"
        @param offset "The offset in the view to match at"
        @param match_allocator "The allocator being used to allocate the array of captures"
        @return NO_MATCH if there is no match starting at offset, or a match if there is one
    *>
    fn Match? match_in_view(String view, usz offset, Allocator match_allocator);

    <*
        Releases the memory used to describe the regex, may be empty on a compile time implementation
    *>
    fn void free();
}

struct Match {
    Allocator allocator;
    String fullView;
    <* captureBegin is inclusive *>
    usz[*] captureBegin;
    <* captureEnd is exclusive *>
    usz[*] captureEnd;
    ushort numCaptures;
}