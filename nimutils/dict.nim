## When we also hook up our single-threaded implementation, this will
## multiplex the Dict interface statically, depending on whether or
## not threads are used.
when compileOption("threads"):
  import "."/crownhash
  export crownhash
