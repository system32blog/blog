+++
title = "Post and Collaboration Guide"
date = "2021-08-20"
description = "An article describing the process to collaborate on the blog."
featured = true
tags = [
    "Robin Beismann"
]
categories = [
    "blogging"
]
series = [""]
aliases = [""]
thumbnail = "images/building.png"
+++
This article offers a quick guide on how to collaborate on the blog and submit / update posts.
<!--more-->

# Introduction
The system32.blog is powered by a static site generator called Hugo and the [Clarity Theme](https://github.com/chipzoller/hugo-clarity).
All content is written in Markdown and hosted on Github which allows anyone to submit posts or collaborate on existing ones.

# How to contribute?
To contibute to the block, please fork the repository [system32blog/blog](https://github.com/system32blog/blog) and update or add a post under `/content/post`.
If your change is ready in your opinion, please raise a pull request to the `preview` branch on [system32blog/blog](https://github.com/system32blog/blog).

`Scroll down further to see a video which describes the process.`

# Preview posts
After your pull request was accepted, you can preview your post on [preview.system32.blog](https://preview.system32.blog).
We'll review the formatting there and move it into the `master` branch.

# Posting
To submit a new post, please create a new file under [`/content/post/`](https://github.com/system32blog/blog/tree/preview/content/post) with a meaningful name like `20210821_grouppolicy.md`, please add the date in the format `YYYYMMDD` like on the example.

The post needs a set of metadata information, please follow this guidance.
## Syntax
```markdown
+++
title = "Post and Collaboration Guide" <!--- A meaningful title --->
date = "2021-08-20" # Date in Format yyyy-MM-dd --->
description = "An article describing the process to collaborate on the blog." <!--- A short description for the search engine --->
featured = false <!--- Please don't change --->
tags = [
    "Robin Beismann" <!--- Put yourself as author here, realname, nickname or github username is fine --->
]
categories = [
    "blogging" <!--- Categories, please have a look at the existing ones or invent a new one if there is none that fits --->
]
series = [""] <!--- If this is a blog series, put a meaningful name here, otherwise leave empty --->
thumbnail = "images/building.png" <!--- Use one of the thumbnails under /images/ or submit a new one. Please note that you need to have the rights on it. --->
+++ <!--- This is a separator, please leave in-place --->
This article offers a quick guide on how to collaborate on the blog and submit / update posts. <!--- The preview line the start page, please leave the next line in-place --->
<!--more--> 

# First heading
More text to follow
```

Feel free to check out the formatting on any other post under [`/content/post/`](https://github.com/system32blog/blog/tree/preview/content/post).

## Referencing media
If you want to reference pictures or other content in your posts, please submit them under ``"/static/post/<your post name without extension>"``.
You can then reference them using:
```markdown
![describing text](logo_red.png)
```

## How to use Visual Studio Code for Git in a Webbrowser
This animation shows how you can check in posts without any Git Client or Markdown editor on your computer.
![example animation](howtopost.gif)