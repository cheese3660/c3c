module std::regex::parsed::automata;
import std::regex;

enum TransitionType : char {
    EPSILON,
}

union EdgeData {
    struct {
        uint stringBegin;
        uint stringEnd;
    }
    usz arrayOffset;
}

<*
    Regex implementation composed of a set of NFAs 
*>
struct Automata (Regex)
{
    Allocator allocator;
    
    <* How many automata are in this automata set *>
    ushort automataCount;
    <* The begin state number of the Nth automaton *>
    uint* automatonBegin;
    <* The end state number of the Nth automaton *>
    uint* automatonEnd;

    <* How many states exist across all automata within this set *>
    uint stateCount;
    <* The offset into the edges table that this states edges begin at *>
    usz* stateEdgesBegin;
    <* The amount of edges this state has *>
    ushort* stateEdgeCount;

    <* How many edges exist in this automata *>
    usz edgeCount;
    <* Where does the edge transition to *>
    uint* edgeTo;
    <* What type of transition does this edge make *>
    TransitionType* transitionType;
    <* What capture group does this edge begin (0 if none) *>
    ushort* edgeCaptureBegin;
    <* What capture group does this edge end (0 if none) *>
    ushort* edgeCaptureEnd;
    <*
        Data associated with this edge depending on the transition type
    *>
    EdgeData* edgeAssociatedData;

    <* Character classes for matching character groups*>
    CharacterClass[] characterClass;

    <* All string matches concatenated together in one array *>
    char[] strings;
}

<*
    @param view: "The string view being matched over"
    @param offset: "The offset in the view to match at"
    @param match_allocator: "The allocator being used to allocate the array of captures"
    @return? regex::NO_MATCH : "If there is no match starting at the offset"
    @return "A match starting at the offset"

    @require offset < view.len
*>
fn Match? Automata.match_in_view(&self, String view, usz offset, Allocator match_allocator) @dynamic {
    return regex::NO_MATCH?;
}


fn void Automata.free(&self) @dynamic {
    allocator::free(self.allocator, self.automatonBegin);
    allocator::free(self.allocator, self.automatonEnd);
    allocator::free(self.allocator, self.stateEdgesBegin);
    allocator::free(self.allocator, self.stateEdgeCount);
    allocator::free(self.allocator, self.edgeTo);
    allocator::free(self.allocator, self.transitionType);
    allocator::free(self.allocator, self.edgeCaptureBegin);
    allocator::free(self.allocator, self.edgeCaptureEnd);
    allocator::free(self.allocator, self.edgeAssociatedData);
    allocator::free(self.allocator, self.characterClass);
    allocator::free(self.allocator, self.strings);
}