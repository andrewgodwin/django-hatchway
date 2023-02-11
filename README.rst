django-hatchway
===============

Hatchway is an API framework inspired by the likes of FastAPI, but while trying
to keep API views as much like standard Django views as possible.

It was built for, and extracted from, `Takahē <https://github.com/jointakahe/takahe>`_;
if you want to see an example of it being used, browse its
`api app <https://github.com/jointakahe/takahe/tree/main/api>`_.


Installation
------------

Install Hatchway from PyPI::

    pip install django-hatchway

And add it to your ``INSTALLED_APPS``::

    INSTALLED_APPS = [
        ...
        "hatchway",
    ]


Usage
-----

To make a view an API endpoint, you should write a standard function-based
view, and decorate it with ``@api_view.get``, ``@api_view.post`` or similar::

    from hatchway import api_view

    @api_view.get
    def my_api_endpoint(id: int, limit: int = 100) -> list[str]:
        ...


The types of your function arguments matter; Hatchway will use them to work out
where to get their values from and how to parse them. All the standard Python
types are supported, plus `Pydantic-style models <https://docs.pydantic.dev/>`_
(which ideally you should build based on the ``hatchway.Schema`` base class,
as it understands how to load things from Django model instances).

Your return type also matters - this is what Hatchway uses to work out how to
format/validate the return value. You can leave it off, or set it to ``Any``,
if you don't want any return validation.

URL Patterns
~~~~~~~~~~~~

You add API views in your ``urls.py`` file like any other view::

    urlpatterns = [
        ...
        path("api/test/", my_api_endpoint),
    ]

The view will only accept the method it was decorated with (e.g. ``GET`` for
``api_view.get``).

If you want to have two or more views on the same URL but responding to
different methods, use Hatchway's ``methods`` object::

    from hatchway import methods

    urlpatterns = [
        ...
        path(
            "api/post/<id>/",
            methods(
                get=posts.post_get,
                delete=posts.posts_delete,
            ),
        ),
    ]


Argument Sourcing
~~~~~~~~~~~~~~~~~

There are four places that input arguments can be sourced from:

* **Path**: The URL of the view, as provided via kwargs from the URL resolver
* **Query**: Query parameters (``request.GET``)
* **Body**: The body of a request, in either JSON, formdata, or multipart format
* **File**: Uploaded files, as part of a multipart body

By default, Hatchway will pull arguments from these sources:

* Standard Python singular types (``int``, ``str``, ``float``, etc.): Path first, and then Query
* Python collection types (``list[int]``, etc.): Query only, with implicit list conversion of either one or multiple values
* ``hatchway.Schema``/Pydantic BaseModel subclasses: Body only (see Model Sourcing below)
* ``django.core.files.File``: File only

You can override where Hatchway pulls an argument from by using one of the
``Path``, ``Query``, ``Body``, ``File``, ``QueryOrBody``, ``PathOrQuery``,
or ``BodyDirect`` annotations::

    from hatchway import api_view, Path, QueryOrBody

    @api_view.post
    def my_api_endpoint(id: Path[int], limit: QueryOrBody[int] = 100) -> dict:
        ...

While ``Path``, ``Query``, ``Body`` and ``File`` force the argument to be
picked from only that source, there are some more complex ones in there:

* ``PathOrQuery`` first tries the Path, then tries the Query (the default for simple types)
* ``QueryOrBody`` first tries the Query, then tries the Body
* ``BodyDirect`` forces top-level population of a model - see Model Sourcing, below.

Model Sourcing
~~~~~~~~~~~~~~

When you define a ``hatchway.Schema`` subclass (or any other pydantic model
subclass), Hatchway will presume that it should pull it from the POST/PUT/etc.
body.

How it pulls it depends on how many body-sourced arguments you have:

* If you just have one, it will feed it the top-level keys in the body data as
  its internal values.

* If you have more than one, it will look for its data in a sub-key named the
  same as the argument name.

For example, this function has two body-sourced things (one implicit, one explicit)::

    @api_view.post
    def my_api_endpoint(thing: schemas.MyInputSchema, limit: Body[int] = 100):
        ...

This means Hatchway will feed the ``schemas.MyInputSchema`` model whatever it
finds under the ``thing`` key in the request body as its input, and ``limit``
will come from the ``limit`` key.

If ``limit`` wasn't specified, then there would be only one body-sourced item,
and Hatchway would feed ``schemas.MyInputSchema`` the entire request body as
its input.

You can force a schema subclass to be fed the entire request body by using the
``BodyDirect[MySchemaClass]`` annotation on its type.

Return Values
~~~~~~~~~~~~~

The return value of an API view, if provided, is used to validate and coerce
the type of the response::

    @api_view.delete
    def my_api_endpoint() -> int:
        ...

It can be either a normal Python type, or a ``hatchway.Schema`` subclass. If
it is a Schema subclass, the response will be fed to it for coercion, and ORM
objects are supported - returning a model instance, a dict with the model
instance values, or an instance of the schema are all equivalent.

A typechecker will honour these too, so we generally recommend returning
instances of your Schema so that your entire view benefits from typechecking,
rather than relying on the coercion. You'll get typechecking in your Schema
subclass constructors, and then typechecking that you're always returnining
the right things from the view.

You can also use generics like ``list[MySchemaClass]`` or
``dict[str, MySchemaClass]`` as a response type; generally, anything Pydantic
allows, we do as well.

Adding Headers/Status Codes to the Response
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you want to do more to your response than just sling some data back at your
client, you can return an ApiResponse object instead of a plain value::

    from hatchway import api_view, ApiResponse

    @api_view.delete
    def my_api_endpoint() -> ApiResponse[int]:
        ...
        return ApiResponse(42, headers={"X-Safe-Delete": "no"})

``ApiResponse`` is a standard Django ``HTTPResponse`` subclass, so accepts
almost all of the same arguments, and has most of the same methods. Just don't
edit its ``.content`` value; if you want to mutate the data you passed into
it, that is stored in ``.data``.

Note that we also changed the return type of the view so that it would pass
typechecking; ``ApiResponse`` accepts any response type as its argument and
passes it through to the same validation layer.

Auto-Collections
~~~~~~~~~~~~~~~~

Hatchway allows you to say that Schema subclasses can pull their values from
individual query parameters or body values; these are normally flat strings,
though, unless you're looking at a JSON-encoded body, or multiple repeated
query parameters.

However, it will respect the use of ``name[]`` to make lists, and ``name[key]``
to make dicts. Some examples:

* A ``a=Query[list[int]]`` argument will see ``url?a=1`` as ``[1]``,
  ``url?a=1&a=2`` as ``[1, 2]``, and ``url?a[]=1&a[]=2`` as ``[1, 2]``.

* A ``b=Body[dict[str, int]]`` argument will correctly accept the POST data
  ``b[age]=30&b[height]=180`` and give you ``{"age": 30, "height": 180}``.

These will also work in JSON bodies too, though of course you don't need them
there; nevertheless, they still work for compatibility reasons.
