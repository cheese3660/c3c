module std::regex;
import std::regex::parsed::automata;

alias RuntimeRegex = automata::NfaRegex;

faultdef NO_MATCH;

<*
    Options that change how regexes behave
*>
enum Options : const char {
    <* Default regex behaviour *>
    NONE = 0,
    <* $ and ^ match on lines instead of the full string *>
    MULTILINE = 1,
    <* . consumes any amount characters *>
    SINGLE_LINE = 2
}

<*
    An interface for a regex implementation, done such that making compiled regular expressions can be much easier in the future
*>
interface Regex {
    <*
        @param view: "The string view being matched over"
        @param offset: "The offset in the view to match at"
        @param matchAllocator: "The allocator being used to allocate the array of captures"
        @return? NO_MATCH : "If there is no match starting at the offset"
        @return "A match starting at the offset"
    *>
    fn Match? match_in_view(String view, usz offset, Allocator matchAllocator);

    <*
        Releases the memory used to describe the regex, may be empty on a compile time implementation
    *>
    fn void free();
}


import std::io;
fn void Regex.print(&self) {
    io::printn("Test");
}

struct Match {
    Allocator allocator;
    String fullView;
    <* captureBegin is inclusive*>
    usz *captureBegin;
    <* captureEnd is exclusive*>
    usz *captureEnd;
    ushort numCaptures;
}


fn void Match.free(&self) {
    allocator::free(self.allocator,self.captureBegin);
    allocator::free(self.allocator,self.captureEnd);
}