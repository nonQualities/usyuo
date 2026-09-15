module backend::index;
import backend::ast;
import backend::arena;
import std::collections::map;
import std::io;

struct PostingNode
{
    int task_id;
    PostingNode* next;
}


struct InvertedIndex
{
    HashMap{String, PostingNode*} map;
}

fn void InvertedIndex.init(&self, Allocator allocator)
{
    self.map.init(allocator);
}

fn void InvertedIndex.free(&self)
{
    self.map.free();
}

fn void InvertedIndex.insert(&self, String tag, int task_id, MemoryArena* arena)
{
    PostingNode* node = (PostingNode*)arena.bump_alloc(PostingNode::size);
    node.task_id = task_id;
    node.next = self.map.get(tag) ?? null;
    self.map[tag] = node;
}

fn PostingNode*? InvertedIndex.lookup(&self, String tag)
{
    return self.map.get(tag);
}


struct TemporalIndex
{
    HashMap{int, PostingNode*} map;
}

fn void TemporalIndex.init(&self, Allocator allocator)
{
    self.map.init(allocator);
}

fn void TemporalIndex.free(&self)
{
    self.map.free();
}

fn void TemporalIndex.insert(&self, int jdn, int task_id, MemoryArena* arena)
{
    if (jdn == 0) return;
    PostingNode* node = (PostingNode*)arena.bump_alloc(PostingNode::size);
    node.task_id = task_id;
    node.next = self.map.get(jdn) ?? null;
    self.map[jdn] = node;
}

fn PostingNode*? TemporalIndex.lookup(&self, int jdn)
{
    return self.map.get(jdn);
}
