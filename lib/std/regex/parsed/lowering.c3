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
    EdgeData associated_data;
    uint next_state;
    ushort capture_begin;
    ushort capture_end;
    TransitionType transition_type;
}

<*
    This describes a singular automaton 
*>
struct SingleAutomaton @private {
    uint begin;
    uint end;
    // List { List {AutomatonEdge } } states;
    List { usz } state_edges_begin;
    List { ushort } state_edge_count;
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
        bool[] keep = mem::temp_array(bool, self.state_edges_begin.len());
        for (usz i = 0; i < self.state_edges_begin.len(); i++) keep[i] = false;
        keep[self.end] = true;
        keep[self.begin] = true;

        // Keep all states that either
        // 1. Have a non-epsilon transition coming into them
        // 2. Have an edge coming out of them that begins or ends a capture group
        // or
        // 3. Have an edge coming into them that begins or ends a capture group
        //
        // 2 is necessary because of how we store capture groups in memory in the engine itself
        for (usz analyzing = 0; analyzing < self.state_edges_begin.len(); analyzing++) 
        {
            usz begin = self.state_edges_begin[analyzing];
            ushort count = self.state_edge_count[analyzing];
            
            for (usz edge_index = begin; edge_index < begin + count; edge_index++) {
                AutomatonEdge *edge = &self.edges[edge_index];
                if (edge.next_state == self.end) continue;
                if (edge.transition_type != EPSILON) keep[edge.next_state] = true;
                
                if (edge.capture_begin != 0 || edge.capture_end != 0) {
                    keep[edge.next_state] = true;
                    keep[analyzing] = true;
                }
            }
        }
        
        uint[] remap = mem::temp_array(uint, self.state_edges_begin.len());

        usz[] old_begin = self.state_edges_begin.to_tarray();
        ushort[] old_count = self.state_edge_count.to_tarray();
        AutomatonEdge[] old_edges = self.edges.to_tarray();

        self.state_edges_begin.clear();
        self.state_edge_count.clear();
        self.edges.clear();


        List { uint } state_stack;
        List { usz }  edge_stack;

        for (uint reducing = 0; reducing < old_begin.len; reducing++) 
        {
            if (reducing == self.end) {
                self.state_edges_begin.push(0);
                self.state_edge_count.push(0);
                continue;
            }

            if (!keep[reducing]) continue;
            
            state_stack.clear();
            edge_stack.clear();
            state_stack.push(reducing);
            edge_stack.push(0);

            usz new_edge_begin = self.edges.len();
            ushort new_count = 0;

            while (state_stack.len() > 0) 
            {
                uint curStateIdx = state_stack.pop()!!;
                usz curEdgeIdx = edge_stack.pop()!!;

                if (curEdgeIdx + 1 < old_count[curStateIdx]) 
                {
                    state_stack.push(curStateIdx);
                    edge_stack.push(curEdgeIdx + 1);
                }

                AutomatonEdge edge = old_edges[old_begin[curStateIdx] + curEdgeIdx];

                if (!keep[edge.next_state]) 
                {
                    state_stack.push(edge.next_state);
                    edge_stack.push(0);
                } 
                else 
                {
                    self.edges.push(edge);
                    new_count += 1;
                }
            }

            remap[reducing] = (uint)self.state_edges_begin.len();
            self.state_edges_begin.push(new_edge_begin);
            self.state_edge_count.push(new_count);
        }

        foreach (&edge : self.edges)
        {
            edge.next_state = remap[edge.next_state];
        }

        self.begin = remap[self.begin];
        self.end = remap[self.end];
    };
}

<*
    This inserts an automaton into an NfaRegex

    @param [&in] self
    @param [&inout] regex   : "The regex being lowered into"
    @param automaton_index   : "The index of this automaton in the regex"
    @param state_offset      : "The offset of the first state of this automaton"
    @param edge_offset       : "The offset of the first edge of this automaton"

    @require automaton_index < regex.automaton_count : "Invalid automaton index"
    @require state_offset + self.state_edges_begin.len() <= regex.state_count : "Invalid state offset"
    @require edge_offset + self.edges.len() <= regex.state_count : "Invalid edge offset"
*>
fn void SingleAutomaton.insert_into(&self, NfaRegex *regex, ushort automaton_index, uint state_offset, usz edge_offset) @private
{
    regex.automaton_begin[automaton_index] = self.begin + state_offset;
    regex.automaton_end[automaton_index] = self.end + state_offset;
    foreach (i, edgesBegin : self.state_edges_begin) {
        regex.state_edges_begin[i + state_offset] = edgesBegin + edge_offset;
        regex.state_edge_count[i + state_offset] = self.state_edge_count[i];
    }

    foreach (i, &edge : self.edges) {
        regex.edge_to[i + edge_offset] = edge.next_state + state_offset;
        regex.transition_type[i + edge_offset] = edge.transition_type;
        regex.edge_capture_begin[i + edge_offset] = edge.capture_begin;
        regex.edge_capture_end[i + edge_offset] = edge.capture_end;
        regex.edge_associated_data[i + edge_offset] = edge.associated_data;
    }
}

struct InternedStringInfo @private
{
    usz begin;
    usz len;
}

<*
    Unescape and intern a string into a dstring

    @param to_intern                 : "The string to intern"
    @param [&in] internment_cache    : "The internment cache itself"

    @return
*>
fn InternedStringInfo unescape_and_intern_string(String to_intern, DString *internment_cache) @private 
{
    if (internment_cache.len() == 0) internment_cache.tinit();
    @pool() {
        return {};
    };
}