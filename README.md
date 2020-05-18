# CEF
The [Chromium Embedded Framework (CEF)](https://en.wikipedia.org/wiki/Chromium_Embedded_Framework) is a simple framework for
embedding Chromium-based browsers in other applications.

Copyright (c) 2008-2020 Marshall A. Greenblatt.

Portions Copyright (c) 2006-2009 Google Inc. All rights reserved.
___

This repository contains the Linden Lab [autobuild](https://pypi.org/project/autobuild/) scripts required to generate a Linden Lab Autobuild package of [CEF](https://en.wikipedia.org/wiki/Chromium_Embedded_Framework) (excluding the libcef_dll_wrapper, which is built elsewhere) that can be used in the Linden Lab autobuild version of [Dullahan](https://bitbucket.org/lindenlab/dullahan)
___

You will also find a batch file and shell scrfipt in the `tools` directory for building CEF from source. Rather than have documentation here get out of date, you should look in the source code of those scripts - there are plenty of comments and it should be straightforward to follow.