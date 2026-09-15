module backend::ast;
import std::collections::map;
import std::collections::list;

alias StringList = List{String};
alias TagMap = HashMap{String, String};


struct Task
{
    int id;                 
    bool completed;         
    char priority;          
    int completion_jdn;     
    int creation_jdn;       
    int due_jdn;            
    String raw_line;   //raw data     
    String description;     
    StringList contexts;    
    StringList projects;    
    TagMap tags;            
}


fn void Task.free(&self)
{
    self.contexts.free();
    self.projects.free();
    self.tags.free();
}


fn String? Task.get_tag(&self, String key)
{
    return self.tags.get(key);
}

//Fliegel-Van Flandern Algorithm
fn int date_to_jdn(int year, int month, int day)
{
    int a = (14 - month) / 12;
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;
    return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
}

//Richards-Hatcher Algorithm
fn void jdn_to_date(int jdn, int* year, int* month, int* day)
{
    int l = jdn + 68569;
    int n = (4 * l) / 146097;
    l = l - (146097 * n + 3) / 4;
    int i = (4000 * (l + 1)) / 1461001;
    l = l - (1461 * i) / 4 + 31;
    int j = (80 * l) / 2447;
    *day = l - (2447 * j) / 80;
    l = j / 11;
    *month = j + 2 - (12 * l);
    *year = 100 * (n - 49) + i + l;
}


fn int Task.get_effective_jdn(Task* self)
{
    if (self.due_jdn != 0) return self.due_jdn;
    return self.creation_jdn;
}
