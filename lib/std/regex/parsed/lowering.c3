<*
    This module implements lowering a regular expression syntax tree into a set of non-deterministic finite automata
*>
module std::regex::parsed::lowering;

import std::regex::parsed::automata;
import std::collections::list;


<*
    This is an unpacked version of an automaton edge

*>
struct AutomatonEdge @private {
    EdgeData associatedData;
    uint nextState;
    ushort captureBegin;
    ushort captureEnd;
    TransitionType transitionType;
}

<*
    This describes a singular automaton 
*>
struct SingleAutomaton @private {
    uint begin;
    uint end;
    // List { List {AutomatonEdge } } states;
    List { usz } stateEdgesBegin;
    List { ushort } stateEdgeCount;
    List { AutomatonEdge } edges;
}

<* 
    This optimizes redundant states out of an automaton

    @param [&inout] self
*>
fn void SingleAutomaton.reduce(&self) @private 
{
    @pool() 
    {
        bool[] keep = mem::temp_array(bool, self.stateEdgesBegin.len());
        for (usz i = 0; i < self.stateEdgesBegin.len(); i++) keep[i] = false;
        keep[self.end] = true;
        keep[self.begin] = true;

        // Keep all states that either
        // 1. Have a non-epsilon transition coming into them
        // 2. Have an edge coming out of them that begins or ends a capture group
        // or
        // 3. Have an edge coming into them that begins or ends a capture group
        //
        // 2 is necessary because of how we store capture groups in memory in the engine itself
        for (usz analyzing = 0; analyzing < self.stateEdgesBegin.len(); analyzing++) 
        {
            usz begin = self.stateEdgesBegin[analyzing];
            ushort count = self.stateEdgeCount[analyzing];
            
            for (usz edgeIndex = begin; edgeIndex < begin + count; edgeIndex++) {
                AutomatonEdge *edge = &self.edges[edgeIndex];
                if (edge.nextState == self.end) continue;
                if (edge.transitionType != EPSILON) keep[edge.nextState] = true;
                
                if (edge.captureBegin != 0 || edge.captureEnd != 0) {
                    keep[edge.nextState] = true;
                    keep[analyzing] = true;
                }
            }
        }
        
        uint[] remap = mem::temp_array(uint, self.stateEdgesBegin.len());

        usz[] oldBegin = self.stateEdgesBegin.to_tarray();
        ushort[] oldCount = self.stateEdgeCount.to_tarray();
        AutomatonEdge[] oldEdges = self.edges.to_tarray();

        self.stateEdgesBegin.clear();
        self.stateEdgeCount.clear();
        self.edges.clear();


        List { uint } stateStack;
        List { usz }  edgeStack;

        for (uint reducing = 0; reducing < oldBegin.len; reducing++) 
        {
            if (reducing == self.end) {
                self.stateEdgesBegin.push(0);
                self.stateEdgeCount.push(0);
                continue;
            }

            if (!keep[reducing]) continue;
            
            stateStack.clear();
            edgeStack.clear();
            stateStack.push(reducing);
            edgeStack.push(0);

            usz newEdgeBegin = self.edges.len();
            ushort newCount = 0;

            while (stateStack.len() > 0) 
            {
                uint curStateIdx = stateStack.pop()!!;
                usz curEdgeIdx = edgeStack.pop()!!;

                if (curEdgeIdx + 1 < oldCount[curStateIdx]) 
                {
                    stateStack.push(curStateIdx);
                    edgeStack.push(curEdgeIdx + 1);
                }

                AutomatonEdge edge = oldEdges[oldBegin[curStateIdx] + curEdgeIdx];

                if (!keep[edge.nextState]) 
                {
                    stateStack.push(edge.nextState);
                    edgeStack.push(0);
                } 
                else 
                {
                    self.edges.push(edge);
                    newCount += 1;
                }
            }

            remap[reducing] = (uint)self.stateEdgesBegin.len();
            self.stateEdgesBegin.push(newEdgeBegin);
            self.stateEdgeCount.push(newCount);
        }

        foreach (&edge : self.edges)
        {
            edge.nextState = remap[edge.nextState];
        }

        self.begin = remap[self.begin];
        self.end = remap[self.end];
    };
}

<*
    This inserts an automaton into an NfaRegex

    @param [&in] self
    @param [&inout] regex   : "The regex being lowered into"
    @param automatonIndex   : "The index of this automaton in the regex"
    @param stateOffset      : "The offset of the first state of this automaton"
    @param edgeOffset       : "The offset of the first edge of this automaton"

    @require automatonIndex < regex.automatonCount : "Invalid automaton index"
    @require stateOffset + self.stateEdgesBegin.len() <= regex.stateCount : "Invalid state offset"
    @require edgeOffset + self.edges.len() <= regex.stateCount : "Invalid edge offset"
*>
fn void SingleAutomaton.insert_into(&self, NfaRegex *regex, ushort automatonIndex, uint stateOffset, usz edgeOffset) @private
{
    regex.automatonBegin[automatonIndex] = self.begin + stateOffset;
    regex.automatonEnd[automatonIndex] = self.end + stateOffset;
    foreach (i, edgesBegin : self.stateEdgesBegin) {
        regex.stateEdgesBegin[i + stateOffset] = edgesBegin + edgeOffset;
        regex.stateEdgeCount[i + stateOffset] = self.stateEdgeCount[i];
    }

    foreach (i, &edge : self.edges) {
        regex.edgeTo[i + edgeOffset] = edge.nextState + stateOffset;
        regex.transitionType[i + edgeOffset] = edge.transitionType;
        regex.edgeCaptureBegin[i + edgeOffset] = edge.captureBegin;
        regex.edgeCaptureEnd[i + edgeOffset] = edge.captureEnd;
        regex.edgeAssociatedData[i + edgeOffset] = edge.associatedData;
    }
}

struct InternedStringInfo @private
{
    usz begin;
    usz len;
}

<*
    Unescape and intern a string into a dstring

    @param toIntern                 : "The string to intern"
    @param [&in] internmentCache    : "The internment cache itself"

    @return
*>
fn InternedStringInfo unescape_and_intern_string(String toIntern, DString *internmentCache) @private 
{
    if (internmentCache.len() == 0) internmentCache.tinit();
    @pool() {
        return {};
    };
}