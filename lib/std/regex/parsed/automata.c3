<*
    This module contains a runtime non-deterministic finite automata engine for running regular expressions
*>
module std::regex::parsed::automata;

import std::regex;
import std::collections::list;

<*
    The action of an edge in the automaton
*>
enum TransitionType : char
{
    <* Empty transition *>
    EPSILON,

    <* Transition on non-newline (any character if SINGLE_LINE is set), can be repeated *>
    WILDCARD,
    <* Transition on a specific string *>
    STRING,
    <* Transition on character being in character group, can be repeated *>
    POS_CHARACTER,
    <* Transition on character not being in character group, can be repeated *>
    NEG_CHARACTER,
    <* Transition on the following sequence being the same as the referant capture group, can be repeated*>
    BACK_REFERENCE,

    <* Transition if given child automaton matches from the current position *>
    POS_LOOKAHEAD,
    <* Transition if given child automaton does not match from the current position *>
    NEG_LOOKAHEAD,
    <* Transition if at start of string, or start of line if MULTILINE is set *>
    START,
    <* Transition if at end of string, or end of line if SINGLE_LINE is set *>
    END,
    <* Transition if at a word boundary *>
    WORD_BOUNDARY,
    <* Transition if not at a word boundary *>
    NOT_WORD_BOUNDARY
}

union EdgeData 
{
    <* for WILDCARD *>
    struct wildcard 
    {
        ushort repeatCount;
    }

    <* For STRING *>
    struct string 
    {
        uint begin;
        uint len;
    }

    <* For POS_CHARACTER and NEG_CHARACTER *>
    struct character 
    {
        uint index;
        ushort repeatCount;
    }

    <* For BACK_REFERENCE *>
    struct backReference 
    {
        ushort captureGroupIndex;
        ushort repeatCount;
    }

    <* For POS_LOOKAHEAD and NEG_LOOKAHEAD *>
    ushort subAutomatonIndex;
}

<*
    Regex implementation composed of a set of NFAs 
*>
struct NfaRegex (Regex)
{
    Allocator allocator;
    
    <* How many automata are in this regex *>
    ushort automatonCount;
    <* The begin state number of the Nth automaton *>
    uint* automatonBegin;
    <* The end state number of the Nth automaton *>
    uint* automatonEnd;

    <* How many states exist across all automata within this regex *>
    uint stateCount;
    <* The offset into the edges table that this states edges begin at *>
    usz* stateEdgesBegin;
    <* The amount of edges this state has *>
    ushort* stateEdgeCount;

    <* How many edges exist in this regex *>
    usz edgeCount;
    <* Where does the edge transition to *>
    uint* edgeTo;
    <* What type of transition does this edge make *>
    TransitionType* transitionType;
    <* What capture group does this edge begin (0 if none) *>
    ushort* edgeCaptureBegin;
    <* What capture group does this edge end (0 if none) *>
    ushort* edgeCaptureEnd;

    <* Data associated with this edge depending on the transition type *>
    EdgeData* edgeAssociatedData;

    <* Character classes for matching character groups*>
    CharacterClass[] characterClass;

    <* All string matches concatenated together in one array *>
    char[] strings;

    <* How many capture groups there are *>
    ushort numCaptureGroups;

    <* How is this regex configured *>
    Options options;
}

struct CaptureEntry @private 
{
    <* reference count this capture array *>
    uint refCount;
    usz* begin;
    usz* end;
}

<* Context that remains the same while running a regex *>
struct NfaRegexStaticContext @private 
{
    List { CaptureEntry } allocatedCaptures;
}

<*
    Get a new capture array for storing on the stack
    
    @param [&in] self
    @param numCaptureGroups : "How many capture groups does the calling regex have"

    @return "The index of a new capture group array in the capture group arrays table, this index being storable on the stack"
*>
fn uint NfaRegexStaticContext.get_new_capture_array(&self, ushort numCaptureGroups) @private 
{
    foreach (i, &entry : self.allocatedCaptures) {
        if (!entry.refCount) {
            entry.refCount = 1;
            entry.begin = mem::temp_array(usz, numCaptureGroups);
            entry.end = mem::temp_array(usz, numCaptureGroups);
            return (uint)i;
        }
    }
    CaptureEntry entry = {
        1,
        mem::temp_array(usz, numCaptureGroups),
        mem::temp_array(usz, numCaptureGroups)
    };
    self.allocatedCaptures.push(entry);
    return (uint)(self.allocatedCaptures.len() - 1);
}

<*
    Get a new capture array copying a previous capture array group

    @param [&in] self
    @param numCaptureGroups         : "How many capture groups does the calling regex have"
    @param originalCaptureGroupsIdx : "Which capture group array is being copied"

    @require originalCaptureGroupsIdx < self.allocatedCaptures.len()        : "Original capture group array is out of bounds"
    @require self.allocatedCaptures[originalCaptureGroupsIdx].refCount != 0 : "Original capture group array is deallocated"

    @return "The index of a new capture group array in the capture group arrays table, with the captures copied from the original capture group array"
*>
fn uint NfaRegexStaticContext.get_new_capture_array_from(&self, ushort numCaptureGroups, uint originalCaptureGroupsIdx) @private 
{
    uint arrayIndex = self.get_new_capture_array(numCaptureGroups);
    usz* currentArrayBegin = self.allocatedCaptures[originalCaptureGroupsIdx].begin;
    usz* currentArrayEnd = self.allocatedCaptures[originalCaptureGroupsIdx].end;
    usz* nextArrayBegin = self.allocatedCaptures[arrayIndex].begin;
    usz* nextArrayEnd = self.allocatedCaptures[arrayIndex].end;
    for (ushort i = 0 ; i < numCaptureGroups; i++) {
        nextArrayBegin[i] = currentArrayBegin[i];
        nextArrayEnd[i] = currentArrayEnd[i];
    }
    return arrayIndex;
}

<*
    Update a capture group begin index

    @param [&in] self
    @param groupsIdx : "The index of the capture group array being modified"
    @param group     : "The capture group being modified, this is 1 indexed"
    @param begin     : "The updated value for the begin position of the capture group"

    @require groupsIdx < self.allocatedCaptures.len()        : "Capture group array is out of bounds"
    @require self.allocatedCaptures[groupsIdx].refCount != 0 : "Capture group array is deallocated"
*>
fn void NfaRegexStaticContext.update_capture_begin(&self, uint groupsIdx, ushort group, usz begin) @private 
{
    usz* arrayBegin = self.allocatedCaptures[groupsIdx].begin;
    arrayBegin[group] = begin;
} 

<*
    Update a capture group end index

    @param [&in] self
    @param groupsIdx : "The index of the capture group array being modified"
    @param group     : "The capture group being modified, this is 1 indexed"
    @param end       : "The updated value for the begin position of the capture group"

    @require groupsIdx < self.allocatedCaptures.len()        : "Capture group array is out of bounds"
    @require self.allocatedCaptures[groupsIdx].refCount != 0 : "Capture group array is deallocated"
*>
fn void NfaRegexStaticContext.update_capture_end(&self, uint groupsIdx, ushort group, usz end) @private 
{
    usz* arrayEnd = self.allocatedCaptures[groupsIdx].end;
    arrayEnd[group] = end;
} 

<* Designed such that the stack is only consistent of 128 bit values *>
bitstruct NfaRegexStackContextPacked : ulong @private 
{
    uint   captureIndex  : 0 .. 23;
    uint   stateIndex    : 24 .. 47;
    ushort edgeIndex     : 48 .. 63;
}

struct NfaRegexStackContext @private 
{
    NfaRegexStackContextPacked p;
    usz viewIndex;
}

<*
    Return a match at the current position with the current capture groups

    @param self
    @param entry                : "The current capture group array"
    @param view                 : "The string being matched over"
    @param numCaptureGroups     : "The number of capture groups in this regex"
    @param startIndex           : "The index in the view that the regex started matching from"
    @param [&in] matchAllocator : "An allocator to allocate the match's begin and end arrays from"

    @require startIndex < view.len      : "The start index is invalid"
    @require self.viewIndex <= view.len : "The current view index is invalid"

    @return "A match at the given position"
*>
fn Match NfaRegexStackContext.to_match(self, CaptureEntry entry, String view, ushort numCaptureGroups, usz startIndex, Allocator matchAllocator) @private 
{
    usz[] begin = allocator::new_array(matchAllocator, usz, (usz)numCaptureGroups + 1);
    usz[] end = allocator::new_array(matchAllocator, usz, (usz)numCaptureGroups + 1);
    for (usz i = 0; i < numCaptureGroups; i++) 
    {
        begin[i+1] = entry.begin[i];
        end[i+1] = entry.end[i];
    }
    begin[0] = startIndex;
    end[0] = self.viewIndex;
    return {
        matchAllocator,
        view,
        begin,
        end,
        numCaptureGroups + 1
    };
}

<*
    Determine the consumption length for an edge

    @param [&in] self
    @param edgeOffset   : "The index of the edge in the relevant tables"
    @param captures     : "The current capture group array"

    @require edgeOffset < self.edgeCount: "Edge is out of bounds"

    @return "How many characters are consumed by the given edge"
*>
fn usz NfaRegex.get_consumption_length(&self, usz edgeOffset, CaptureEntry captures) @private 
{
    EdgeData data = self.edgeAssociatedData[edgeOffset];
    switch (self.transitionType[edgeOffset]) 
    {
        case WILDCARD:
            return data.wildcard.repeatCount;
        case STRING:
            return data.string.len;
        case POS_CHARACTER:
            return data.character.repeatCount;
        case NEG_CHARACTER:
            return data.character.repeatCount;
        case BACK_REFERENCE:
            return (captures.end[data.backReference.captureGroupIndex - 1] - captures.begin[data.backReference.captureGroupIndex - 1]) * data.backReference.repeatCount;
        case EPSILON:
        case POS_LOOKAHEAD:
        case NEG_LOOKAHEAD:
        case START:
        case END:
        case WORD_BOUNDARY:
        case NOT_WORD_BOUNDARY:
            return 0;
    }
}

<*
    @param c : "The character being checked"

    @return "True if the character is alphanumeric or an underscore"
*>
fn bool is_word_character(char c) @private 
{
    return c.is_alnum() || c == '_';
}

<*
    Determine if the automaton should transition at this edge

    @param [&in] self
    @param edgeOffset   : "The index of the edge in the relevant tables"
    @param currentIndex : "The current index into the view"
    @param view         : "The string being matched upon"
    @param captures     : "The current capture array"

    @require edgeOffset < self.edgeCount: "Edge is out of bounds"
*>
fn bool NfaRegex.should_transition(&self, usz edgeOffset, usz currentIndex, String view, CaptureEntry captures) @private 
{
    EdgeData data = self.edgeAssociatedData[edgeOffset];
    switch (self.transitionType[edgeOffset]) 
    {
        case EPSILON:
            return true;
        case WILDCARD:
            if (self.options & Options.SINGLE_LINE) 
            {
                return true;
            }
            for (usz i = currentIndex; i < currentIndex + data.wildcard.repeatCount; i++) 
            {
                if (view[i] == '\n') return false;
            }
            return true;
        case STRING:
            return view[currentIndex..].starts_with((String)(self.strings[data.string.begin:data.string.len]));
        case BACK_REFERENCE:
            usz begin = captures.begin[data.backReference.captureGroupIndex - 1];
            usz end = captures.end[data.backReference.captureGroupIndex - 1];
            if (begin == end) return true;
            if (begin > end) return false;
            if (begin >= view.len) return false;
            if (end > view.len) return false;
            String toCheck = view[begin..end-1];
            for (usz i = 0; i < data.backReference.repeatCount; i++) 
            {
                if (!view[currentIndex + (toCheck.len * i)..].starts_with(toCheck)) return false;
            }
            return true;
        case POS_CHARACTER:
            CharacterClass class = self.characterClass[data.character.index];
            for (usz i = currentIndex; i < currentIndex + data.character.repeatCount; i++) 
            {
                if (!class[view[i]]) return false;
            }
            return true;
        case NEG_CHARACTER:
            CharacterClass class = self.characterClass[data.character.index];
            for (usz i = currentIndex; i < currentIndex + data.character.repeatCount; i++) 
            {
                if (class[view[i]]) return false;
            }
            return true;
        case START:
            if (self.options & Options.MULTILINE) 
            {
                return currentIndex == 0 || (view[currentIndex - 1] == '\n');
            }
            return currentIndex == 0;
        case END:
            if (self.options & Options.MULTILINE) 
            {
                return currentIndex == view.len || (view[currentIndex] == '\n');
            }
            return currentIndex == view.len;
        case WORD_BOUNDARY:
            if (view.len == 0) 
            {
                return false;
            }
            if (currentIndex == 0) 
            {
                return is_word_character(view[currentIndex]);
            }
            if (currentIndex == view.len) 
            {
                return is_word_character(view[currentIndex - 1]);
            }
            return  (is_word_character(view[currentIndex]) && !is_word_character(view[currentIndex-1])) || 
                    (is_word_character(view[currentIndex - 1]) && !is_word_character(view[currentIndex]));
        case NOT_WORD_BOUNDARY:
            if (view.len == 0) 
            {
                return true;
            }
            if (currentIndex == 0) 
            {
                return !is_word_character(view[currentIndex]);
            }
            if (currentIndex == view.len)
            {
                return !is_word_character(view[currentIndex - 1]);
            }
            return  (is_word_character(view[currentIndex]) && is_word_character(view[currentIndex-1])) || 
                    (!is_word_character(view[currentIndex - 1]) && !is_word_character(view[currentIndex]));
        case POS_LOOKAHEAD:
            return self.matches_at(view, currentIndex, data.subAutomatonIndex);
        case NEG_LOOKAHEAD:
            return !self.matches_at(view, currentIndex, data.subAutomatonIndex);
    }
}

<*
    Try and get a match starting at the current offset in the view

    @param [&in] self
    @param view: "The string view being matched over"
    @param offset: "The offset in the view to match at"
    @param matchAllocator: "The allocator being used to allocate the array of captures"

    @require offset < view.len

    @return? regex::NO_MATCH : "If there is no match starting at the offset"
    @return "A match starting at the offset"
*>
fn Match? NfaRegex.match_in_view(&self, String view, usz offset, Allocator matchAllocator) @dynamic 
{
    uint beginState = self.automatonBegin[0];
    uint endState = self.automatonEnd[0];
    @pool() 
    {
        // Setup the initial context
        NfaRegexStaticContext staticContext;
        uint startingCaptureArray = staticContext.get_new_capture_array(self.numCaptureGroups);
        usz* arrayBegin = staticContext.allocatedCaptures[startingCaptureArray].begin;
        usz* arrayEnd = staticContext.allocatedCaptures[startingCaptureArray].end;
        for (ushort i = 0 ; i < self.numCaptureGroups; i++) 
        {
            arrayBegin[i] = usz.max;
            arrayEnd[i] = usz.max;
        }

        List { NfaRegexStackContext } contextStack;

        contextStack.push({
            {
                startingCaptureArray,
                beginState,
                0,
            },
            offset
        });

        while (try currentContext = contextStack.pop()) 
        {    
            uint captureIndex = currentContext.p.captureIndex;
            defer staticContext.allocatedCaptures[captureIndex].refCount -= 1;
            
            uint stateIndex = currentContext.p.stateIndex;
            ushort edgeIndex = currentContext.p.edgeIndex;
            usz currentStateBegin = self.stateEdgesBegin[stateIndex];
            uint edgeCount = self.stateEdgeCount[stateIndex];
            usz edgeOffset = currentStateBegin + edgeIndex;
            usz index = currentContext.viewIndex;

            if (currentContext.p.stateIndex == endState) return currentContext.to_match(staticContext.allocatedCaptures[captureIndex], view, self.numCaptureGroups, offset, matchAllocator);
            
            // Push the next edge if there is one
            if (edgeIndex + 1 < edgeCount) 
            {
                staticContext.allocatedCaptures[captureIndex].refCount += 1;
                contextStack.push({
                    {
                        captureIndex,
                        stateIndex,
                        edgeIndex + 1
                    },
                    index
                });
            }
            
            usz consumptionLength = self.get_consumption_length(edgeOffset, staticContext.allocatedCaptures[captureIndex]);
            
            if (index + consumptionLength > view.len) continue;
            
            if (self.should_transition(edgeOffset, index, view, staticContext.allocatedCaptures[captureIndex])) continue;
            if 
            (
                self.edgeCaptureBegin[edgeOffset] && 
                staticContext.allocatedCaptures[captureIndex].begin[self.edgeCaptureBegin[edgeOffset] - 1] == usz.max
            )
            {
                uint nextGroup = staticContext.get_new_capture_array_from(self.numCaptureGroups, captureIndex);
                staticContext.update_capture_begin(nextGroup, self.edgeCaptureBegin[edgeOffset], index);

                contextStack.push({
                    {
                        nextGroup,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            } 
            else if
            (
                self.edgeCaptureEnd[edgeOffset] &&
                staticContext.allocatedCaptures[captureIndex].end [self.edgeCaptureEnd[edgeOffset] - 1]== usz.max
            ) 
            {
                uint nextGroup = staticContext.get_new_capture_array_from(self.numCaptureGroups, captureIndex);
                staticContext.update_capture_end(nextGroup, self.edgeCaptureEnd[edgeOffset], index);

                contextStack.push({
                    {
                        nextGroup,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            } 
            else 
            {
                staticContext.allocatedCaptures[captureIndex].refCount += 1;

                contextStack.push({
                    {
                        captureIndex,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            }
        }

        return regex::NO_MATCH?;
    };
}

<*
    Check if the given subautoma matches at the index
    
    @param [&in] self
    @param view                 : "The string view being matched over"
    @param offset               : "The offset in the view to match at"
    @param subAutomatonIndex    : "The subautomaton to check"

    @require offset < view.len : "Offset is out of bounds of the string"
    @require subAutomatonIndex < self.automatonCount : "Invalid subautomaton index"

    @return "If the sub-automaton matches at the given offset"

*>
fn bool NfaRegex.matches_at(&self, String view, usz offset, usz subAutomatonIndex) 
{
    uint beginState = self.automatonBegin[subAutomatonIndex];
    uint endState = self.automatonEnd[subAutomatonIndex];
    @pool() 
    {
        // Setup the initial context
        NfaRegexStaticContext staticContext;
        uint startingCaptureArray = staticContext.get_new_capture_array(self.numCaptureGroups);
        usz* arrayBegin = staticContext.allocatedCaptures[startingCaptureArray].begin;
        usz* arrayEnd = staticContext.allocatedCaptures[startingCaptureArray].end;
        for (ushort i = 0 ; i < self.numCaptureGroups; i++) 
        {
            arrayBegin[i] = usz.max;
            arrayEnd[i] = usz.max;
        }

        List { NfaRegexStackContext } contextStack;

        contextStack.push({
            {
                startingCaptureArray,
                beginState,
                0,
            },
            offset
        });

        while (try currentContext = contextStack.pop()) 
        {    
            uint captureIndex = currentContext.p.captureIndex;
            defer staticContext.allocatedCaptures[captureIndex].refCount -= 1;

            uint stateIndex = currentContext.p.stateIndex;
            ushort edgeIndex = currentContext.p.edgeIndex;
            usz currentStateBegin = self.stateEdgesBegin[stateIndex];
            uint edgeCount = self.stateEdgeCount[stateIndex];
            usz edgeOffset = currentStateBegin + edgeIndex;
            usz index = currentContext.viewIndex;

            if (currentContext.p.stateIndex == endState) return true;

            // Push the next edge if there is one
            if (edgeIndex + 1 < edgeCount) 
            {
                staticContext.allocatedCaptures[captureIndex].refCount += 1;
                contextStack.push({
                    {
                        captureIndex,
                        stateIndex,
                        edgeIndex + 1
                    },
                    index
                });
            }
            usz consumptionLength = self.get_consumption_length(edgeOffset, staticContext.allocatedCaptures[captureIndex]);
            if (index + consumptionLength > view.len) continue;
            if (self.should_transition(edgeOffset, index, view, staticContext.allocatedCaptures[captureIndex])) continue;
            if 
            (
                self.edgeCaptureBegin[edgeOffset] && 
                staticContext.allocatedCaptures[captureIndex].begin[self.edgeCaptureBegin[edgeOffset] - 1] == usz.max
            )
            {
                uint nextGroup = staticContext.get_new_capture_array_from(self.numCaptureGroups, captureIndex);
                staticContext.update_capture_begin(nextGroup, self.edgeCaptureBegin[edgeOffset], index);

                contextStack.push({
                    {
                        nextGroup,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            } 
            else if 
            (
                self.edgeCaptureEnd[edgeOffset] && 
                staticContext.allocatedCaptures[captureIndex].end [self.edgeCaptureEnd[edgeOffset] - 1]== usz.max
            ) 
            {
                uint nextGroup = staticContext.get_new_capture_array_from(self.numCaptureGroups, captureIndex);
                staticContext.update_capture_end(nextGroup, self.edgeCaptureEnd[edgeOffset], index);
                
                contextStack.push({
                    {
                        nextGroup,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            } 
            else 
            {
                staticContext.allocatedCaptures[captureIndex].refCount += 1;

                contextStack.push({
                    {
                        captureIndex,
                        self.edgeTo[edgeOffset],
                        0
                    },
                    index + consumptionLength
                });
            }
        }
        return false;
    };
}

fn void NfaRegex.free(&self) @dynamic 
{
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