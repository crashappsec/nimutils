import tables, options

type
  ColInfo = object
    minAct, maxAct:   int
    minSpec, maxSpec: int
    fmt:              string
    priority:         int

  TextTable* = object
    colspecs:        seq[ColInfo]
    rows:            seq[seq[string]]
    headerFmt:       Option[string]
    horizontalSep:   char
    headerRowOnly:   bool
    verticalSep:     char
    firstColOnly:    bool
    numColumns:      int
    colFlex:         bool
    intersectionSep: char

proc newTextTable*(columns: int = 0, ): TextTable =
  
    
    

  
